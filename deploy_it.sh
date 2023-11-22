#!/bin/bash

################################################################################
# Project Setup Script
# Author: Prabin
# Description: This Bash script automates the setup process for a web project on
# an Nginx server. It handles package installation, service management, site
# configuration, project deployment, and service restart.
#
# Usage: ./deploy_it.sh <nginx> <nginx> <site-name> <github-repo-link> <project directory name>
#
# Important: This script is intended to run on Ubuntu as sudo.
# Ensure you have backups before running the script.
#
# License: MIT License (see LICENSE file for details)
################################################################################



# Global arguments
package_name=$1
service=$2
site_name=$3
github_repo=$4
source_code_dir_name=$5
server_name=$6

# Check if the required number of arguments is provided.
# Usage: $0 <package name> <service name> <site name> <github_repo> <source_code_dir_name>
#   - Replace placeholders with actual values when running the script.
#   - Exits with status 3 if the expected number of arguments is not provided.
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <package name> <service name> <site name> <github_repo> <source_code_dir_name>"
    echo "Please provide all required arguments."
    exit 3
fi



# Check if the provided GitHub link is valid
get_repo(){
    # Use curl to check the HTTP status of the GitHub repository link
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -L "$github_repo")

    # If the HTTP status is not 200, display an error message and exit with status 4
    if [ $http_status -ne 200 ]; then
        echo "HTTP response from the GitHub repository is not 200. Provide the correct link for your repository. Exiting..."
        exit 4
    else
        # Extract the repository name from the GitHub link
        repo=$(echo "$github_repo" | awk -F/ '{print $NF}' | awk -F"." '{if (NF == 2){ print $(NF -1)} else {print $NF}}')
    fi
}
# Call the get_repo function with the provided GitHub link
get_repo "$github_repo"

# Function to check the status of a command and exit if it fails
# Usage: check_err <command> <status>
#   <command>: The command to be executed
#   <status>: The exit status of the command
# If the status is 0, print success message; otherwise, print an error message and exit with status 1.
check_err(){
    command=$1
    status=$2
    if [ "$status" == "0" ]; then
        echo "[$command] was successful."
    else
        echo "Error while [$command]. Exiting"
        exit 1
    fi
}


# Function to check if a package is installed and install it if not
# Usage: install_it
# - The function checks if the specified package is present using dpkg.
# - If the package is present, it prints a message and skips installation.
# - If the package is not present, it installs the package using apt.
# - The installation is verified using the check_err function.
install_it(){
    # Check if the package is present in the list of installed packages
    package_present=$(dpkg -l | awk '{print $2}' | awk -v package_name="$package_name" '{for(i=1;i<=NF;i++) if($i == package_name ) print "true"}')

    # Print the current value of package_present

    # If package is present, skip installation; otherwise, install the package
    if "$package_present"; then
        echo "$package_name is already installed. Skipping installation..."
    else
        echo "
        $package_name is not installed. Installing now...
        "
        apt install -y "$package_name"
        check_err "apt install -y $package_name" "$?"
    fi
}



# Function to check and start a service if it is not already running
# Usage: start_it
# - The function retrieves the status of the specified service using systemctl.
# - If the service is "active" and "running," it prints a message indicating that the service is already running.
# - If the service is "dead," it prints a message, starts the service using systemctl, and checks for errors using check_err.
# - If the service status is neither "active" nor "dead," it prints a message indicating that the service does not exist.
start_it(){
    # Get the status of the service
    service_status=$(systemctl status nginx | grep -i "active" | awk '{for (i=1; i<=NF; i++){if($i ~ /.running./){print "running"}else if($i ~ /.dead./){print "dead"} else if ($i ~ /failed/){print "failed"}}}')

    # Case statement to handle different service statuses
    case $service_status in
        "running")
        echo "$service is running. Nothing to do."
        ;;
        "dead")
        echo "$service is dead. Starting $service now..."
        systemctl start $service
        check_err "systemctl start $service" "$?"
        ;;
        "failed")
        echo "$service has failed. Exiting..."
	exit 5
	;;
    esac
}


# Function to check and enable a service if it is currently disabled
# Usage: enable_it
# - The function retrieves the boot status of the specified service using systemctl.
# - If the service is already "enabled," it prints a message indicating that the service is already enabled.
# - If the service is "disabled," it prints a message, enables the service using systemctl, and checks for errors using check_err.
enable_it(){
	# Check if the system is enabled and enable it if disabled
	if systemctl is-enabled --quiet $service; then
		echo "service:$service is enabled. Nothing to do"
	else
		echo "service:$service is disabled. Enabling it now.."
		systemctl enable $service >> /dev/null
		check_err "systemctl enable $service" "$?"
	fi
}

get_nginx_user(){
    # Find the path to the nginx configuration file
    path_to_config_file=$(find / -type f -name "nginx.conf")

    # Extract the nginx user from the configuration file
    nginx_user=$(cat "$path_to_config_file" | awk '/user/{print $2}')
    nginx_user=$(echo "$nginx_user" | sed 's/;$//')
}

# Function to create a new site directory and set ownership and permissions
# Usage: create_site
# - The function locates the nginx configuration file and extracts the user specified in the configuration.
# - It then checks if the site directory already exists. If it does, it exits with an error message.
# - If the site directory does not exist, it creates the directory, assigns ownership to the nginx user, and sets appropriate permissions.
create_site(){
    # Find the nginx user name
    get_nginx_user 
    # Find the path to the default site directory
    path_to_default_site_dir=/var/www/html

    # Check if the site directory already exists
    if [ -d "$path_to_default_site_dir/$site_name" ]; then
        echo "$site_name already exists. Try another name. Exiting..."
        exit 2
    else
        # Create the site directory
        mkdir -p  "$path_to_default_site_dir/$site_name"
        path_to_new_site="$path_to_default_site_dir"/"$site_name"
        echo "$path_to_new_site is created."

        # Assign ownership and set permissions for the nginx user
        echo "Assigning ownership and permission to $nginx_user"
        chown "$nginx_user":"$nginx_user" -R "$path_to_new_site"
        chmod 770 -R "$path_to_new_site"
    fi
}

# Function to configure a new Nginx site
# Usage: configure_site
# - Creates a new configuration file for the specified site in /etc/nginx/sites-available.
# - The configuration includes basic server settings, such as root directory, index files, server name or IP, and location settings.
# - Creates a symbolic link in /etc/nginx/sites-enabled to enable the new site.
configure_site(){
    # Create a new configuration file for the site in sites-available
    echo "Creating a Vhost for $site_name"
    site="$site_name".conf
    touch /etc/nginx/sites-available/$site
    cat > /etc/nginx/sites-available/$site << EOF
    server {
        listen 80;
        root $path_to_new_site;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;
        server_name $server_name;
        location / {
            # First attempt to serve request as file, then
            # as directory, then fall back to displaying a 404.
            try_files \$uri \$uri/ =404;
        }
    }
EOF

    # Create a symbolic link to enable the new site
    ln -s /etc/nginx/sites-available/$site /etc/nginx/sites-enabled/
}

deploy_it(){
    echo "Pulling the source code from the repo $github_repo"
    git clone -q "$github_repo" 
    # Display a message and change into the specified project directory
    # Copying all files and folders in the project directory to the specified site directory
    echo "Coping the files and folders to the $path_to_new_site"
    cp -R  "$repo"/"$source_code_dir_name"/*  "$path_to_new_site"
    rm -R  "$repo"
    # Restart the specified service
    echo "Restarting $service now..."
    systemctl restart $service
    check_err "systemctl restart $service" "$?"
}



# Update package information using 'apt update' with the '-y' flag for automatic confirmation.
echo "Updating the system ..."
apt update -y > /dev/null 2>&1 | tee log_error.txt

# Check the exit status of the 'apt update' command using the 'check_err' function.
# The first argument is the command executed, and the second argument is its exit status.
# If the exit status is non-zero, print an error message and exit with status 1; otherwise, indicate a successful update.
check_err "apt update -y" "$?"

# Invoke the 'install_it' function with the specified package name.
# The 'install_it' function checks whether the package is already installed.
# If the package is not installed, it installs the package using 'apt install -y'.
# The 'check_err' function is used to verify the success of the installation.
echo "Installing the package if not already installed. but 'll skip if installed."
install_it "$package_name"


# Start the specified service using the 'start_it' function.
# The 'start_it' function checks the current status of the service and takes appropriate actions:
# - If the service is already running, it prints a message indicating that the service is running.
# - If the service is dead, it prints a message, starts the service using 'systemctl start', and checks for errors using 'check_err'.
# - If the service does not exist, it prints a message indicating that there is nothing to start.
echo "Starting service if not already installed.."
start_it "$service"

# Enable the specified service using the 'enable_it' function.
# The 'enable_it' function checks the boot status of the service and takes appropriate actions:
# - If the service is already enabled, it prints a message indicating that the service is enabled.
# - If the service is disabled, it prints a message, enables the service using 'systemctl enable', and checks for errors using 'check_err'.
# - If the boot status is neither 'enabled' nor 'disabled', it prints a message indicating that there is nothing to do.
echo "Enabling the service if disabled."
enable_it "$service"


# Create a new site using the 'create_site' function with the specified site name.
# The 'create_site' function performs the following tasks:
# - Locates the nginx configuration file and extracts the nginx user.
# - Checks if the site directory already exists; if it does, it exits with an error message.
# - If the site directory does not exist, it creates the directory, assigns ownership to the nginx user, and sets appropriate permissions.
create_site "$site_name"

# Configure the Nginx site using the 'configure_site' function with the specified site name.
# The 'configure_site' function performs the following tasks:
# - Calls the 'remove_default' function to ensure the default Nginx site is removed.
# - Creates a new configuration file for the specified site in /etc/nginx/sites-available.
# - The configuration includes basic server settings, such as root directory, index files, server name or IP, and location settings.
# - Creates a symbolic link in /etc/nginx/sites-enabled to enable the new site.
configure_site "$site_name" "$server_name"

# Pull the source code from the git hub repo and CD into that repo
# Move the content of the repo into the new site directory
# Restart the nginx service
deploy_it "$github_repo" "$source_code_dir_name"
