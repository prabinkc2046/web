#!/bin/bash

################################################################################
# Project Setup Script
# Author: Prabin
# Description: This Bash script automates the setup process for a web project on
# an Nginx server. It handles package installation, service management, site
# configuration, project deployment, and service restart.
#
# Usage: ./deploy_it.sh <site-name> <github-repo-link> <project directory name> <server-name>
#
# Important: This script is intended to run on Ubuntu as sudo.
# Ensure you have backups before running the script.
#
# License: MIT License (see LICENSE file for details)
################################################################################



# Global arguments
site_name=$1
github_repo=$2
source_code_dir_name=$3
server_name=$4

# Check if the required number of arguments is provided.
# Usage: $0 <site name> <github_repo> <source_code_dir_name> <server_name>
#   - Replace placeholders with actual values when running the script.
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <site name> <github_repo> <source_code_dir_name> <server_name>"
    exit
fi

# Check if the provided GitHub link is valid
get_repo(){
    # Use curl to check the HTTP status of the GitHub repository link
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -L "$github_repo")

    # If the HTTP status is not 200, display an error message and exit with status 4
    if [ $http_status -ne 200 ]; then
        echo "HTTP response from the GitHub repository is not 200. Provide the correct link for your repository. Exiting..."
        exit
    else
        # Extract the repository name from the GitHub link
        repo=$(echo "$github_repo" | awk -F/ '{print $NF}' | awk -F"." '{if (NF == 2){ print $(NF -1)} else {print $NF}}')
    fi
}

# Call the get_repo function with the provided GitHub link
get_repo "$github_repo"

# Check if the provided project directory exists
project_dir_exists=""
check_if_project_dir_exists(){
    #Move into the repo
    cd "$repo"
    # check if provided directory exists
    if [ -d "$source_code_dir_name" ]; then
        project_dir_exists="yes"
    else
        project_dir_exists="no"
    fi
}

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
        exit
    fi
}

# Detects the Linux distribution
distro=""
detect_distro(){
    # Source the os-release file to get information about the operating system
    source /etc/os-release

    # Check if the ID field is non-empty
    if [ -n "$ID" ]; then
        # Convert the ID to lowercase and assign it to the 'distro' variable
        distro=$(echo "$ID" | tr '[:upper:]' '[:lower:]' )
    else
        # Print an error message if the distro is not detected
        echo "Error: Distro not detected. This script is not suitable for running on this operating system."
    fi
}
detect_distro


# Function to check if a package is installed and install it if not
# Usage: install_it
# - The function checks if the specified package is present using dpkg.
# - If the package is present, it prints a message and skips installation.
# - If the package is not present, it installs the package using apt.
# - The installation is verified using the check_err function.
install_it(){
    packages=(nginx git)
    for package_name in ${packages[@]}; do
        case $distro in
        "ubuntu"|"debian")
            if dpkg -l | grep -iq $package_name; then
                echo "$package_name is already installed. Skipping installation..."
            else
                echo "$package_name is not installed. Installing now..."
                apt install "$package_name" -y  >> /dev/null
                check_err "apt install -y $package_name" "$?"
            fi
            ;;
        "fedora"|"centos")
            if rpm -q --quiet $package_name; then
                echo "$package_name is already installed. Skipping installation..."
            else
                echo "$package_name is not installed. Installing now..."
                dnf install "$package_name" -y  >> /dev/null
                check_err "dnf install $package_name" "$?"
            fi
            ;;
        esac
    done
}

# Function to check and start a service if it is not already running
# Usage: start_it
# - The function retrieves the status of the specified service using systemctl.
# - If the service is "active" and "running," it prints a message indicating that the service is already running.
# - If the service is "dead," it prints a message, starts the service using systemctl, and checks for errors using check_err.
start_it(){
    # Get the status of the service
    service_status=$(systemctl status nginx | grep -i "active" | awk '{for (i=1; i<=NF; i++){if($i ~ /.running./){print "running"}else if($i ~ /.dead./){print "dead"} else if ($i ~ /failed/){print "failed"}}}')

    # Case statement to handle different service statuses
    case $service_status in
        "running")
        echo "nginx is already running. No need to start it."
        ;;

        "dead")
        echo "nginx is dead. Starting it now..."
        systemctl start nginx
        check_err "systemctl start nginx" "$?"
        ;;

        "failed")
        echo "nginx has failed. Exiting..."
	    exit
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
	if systemctl is-enabled --quiet nginx; then
		echo "nginx is enabled. No need to enable it."
	else
		echo "nginx is disabled. Enabling it now.."
		systemctl enable nginx >> /dev/null
		check_err "systemctl enable nginx" "$?"
	fi
}

# Retrieves the Nginx user from the configuration file
get_nginx_user(){
    # Specify the path to the nginx configuration file
    path_to_config_file=/etc/nginx/nginx.conf

    # Extract the Nginx user from the configuration file using grep and awk
    nginx_user=$(cat "$path_to_config_file" | grep "user" | awk 'NR == 1{print $2}')

    # Remove the trailing semicolon, if present, from the Nginx user
    nginx_user=$(echo "$nginx_user" | sed 's/;$//')

    # Display a message indicating the Nginx user found
    echo "Nginx user found: $nginx_user"
}

# Create a new site directory with specified ownership and permissions
create_site(){
    # Call the get_nginx_user function to determine the Nginx user
    get_nginx_user
    echo "Creating a $site_name under $nginx_user ownership"

    # Use a case statement to handle different Linux distributions
    case $distro in
        "ubuntu"|"debian")
            # Define the path to the default site directory for Ubuntu/Debian
            path_to_default_site_dir=/var/www/html

            # Check if the site directory already exists
            if [ -d "$path_to_default_site_dir/$site_name" ]; then
                echo "$site_name already exists. Give a different name for the site. Exiting..."
                exit
            else
                # Create the site directory
                mkdir -p  "$path_to_default_site_dir/$site_name"
                path_to_new_site="$path_to_default_site_dir"/"$site_name"
                echo "New site directory $path_to_new_site is created."

                # Assign ownership and set permissions for the Nginx user
                echo "Assigning ownership and permissions to $nginx_user for site $path_to_new_site"
                chown "$nginx_user":"$nginx_user" -R "$path_to_new_site"
                chmod 770 -R "$path_to_new_site"
            fi
            ;;

        "fedora"|"centos")
            # Define the path to the default site directory for Fedora/CentOS
            path_to_default_site_dir=/usr/share/nginx/html

            # Check if the site directory already exists
            if [ -d "$path_to_default_site_dir/$site_name" ]; then
                echo "$site_name already exists. Try another name. Exiting..."
                exit
            else
                # Create the site directory
                mkdir -p  "$path_to_default_site_dir/$site_name"
                path_to_new_site="$path_to_default_site_dir"/"$site_name"
                echo "New site directory $path_to_new_site is created."

                # Assign ownership and set permissions for the Nginx user
                echo "Assigning ownership and permissions to $nginx_user for site $path_to_new_site"
                chown "$nginx_user":"$nginx_user" -R "$path_to_new_site"
                chmod 770 -R "$path_to_new_site"
            fi
            ;;
    esac
}


# Configure a new Nginx site based on the detected Linux distribution
configure_site(){
    case $distro in
        "ubuntu"|"debian")
            # Create a new configuration file for the site in sites-available
            echo "Creating a virtual host for $site_name"
            site="$site_name".conf

            # Use a here document to create the Nginx configuration
            cat > /etc/nginx/sites-available/$site << EOF
            server {
                listen 80;
                root $path_to_new_site;
                # Add index.php to the list if you are using PHP
                index index.html index.htm index.nginx-debian.html;
                server_name $server_name;
                location / {
                    try_files \$uri \$uri/ =404;
                }
            }
EOF
            # Create a symbolic link to enable the new site
            ln -s /etc/nginx/sites-available/$site /etc/nginx/sites-enabled/
            ;;

        "fedora")
            # Create a new configuration file for the site in conf.d directory
            echo "Creating a virtual host for $site_name"
            site="$site_name".conf

            # Use a here document to create the Nginx configuration
            cat > /etc/nginx/conf.d/$site << EOF
            server {
                listen 80;
                root $path_to_new_site;
                index index.html index.htm index.nginx-debian.html;
                server_name $server_name;
                location / {
                    try_files \$uri \$uri/ =404;
                }
            }
EOF
            ;;
    esac
}

# Deploy the source code from the specified GitHub repo to the Nginx site directory
deploy_it(){
    echo "Pulling the source code from the repo $github_repo"
    # Clone the GitHub repo quietly
    git clone -q "$github_repo"

    # Display a message and check if the source code project directory exists
    echo "Checking if the source code project directory exists"
    check_if_project_dir_exists

    # Check if the project directory exists and proceed accordingly
    if [ "project_dir_exists" = "yes" ]; then
        echo "$source_code_dir_name exists in $repo. Deployment starting shortly..."
        echo "Copying the files and folders to the $path_to_new_site"
        # Copy the content of the project directory to the specified site directory
        cp -R  "$source_code_dir_name"/*  "$path_to_new_site"
        # Remove the cloned repo directory
        rm -R  ../"$repo"
        # Restart the specified service
        echo "Restarting nginx now..."
        systemctl restart nginx
        check_err "systemctl restart nginx" "$?"
    else
        echo "$source_code_dir_name does not exist in $repo. Deploying whatever $repo contains..."
        echo "Copying the files and folders to the $path_to_new_site"
        # Copy all files and folders in the repo to the specified site directory
        cp -R  *  "$path_to_new_site"
        # Remove the cloned repo directory
        rm -R  ../"$repo"
        # Restart the specified service
        echo "Restarting nginx now..."
        systemctl restart nginx
        check_err "systemctl restart nginx" "$?"
    fi
}


# Update package information based on the detected distribution of the operating system.
update_it(){
    echo "Updating the system ..."

    # Use a case statement to determine the package manager based on the detected distribution
    case $distro in
    "ubuntu"|"debian")
        # Update using apt for Debian-based systems
        apt update -y >> /dev/null 2>&1 | tee log_error.txt
        check_err "apt update -y" "$?"
        ;;
    "fedora"|"centos")
        # Update using dnf for Fedora/CentOS systems
        dnf update -y >> /dev/null 2>&1 | tee log_error.txt
        check_err "dnf update -y" "$?"
        ;;
    esac
}


#Update system package
update_it

# Invoke the 'install_it' function with the specified package name.
# The 'install_it' function checks whether the package is already installed.
# If the package is not installed, it installs the package using 'apt install -y'.
# The 'check_err' function is used to verify the success of the installation.
install_it


# Start the specified service using the 'start_it' function.
# The 'start_it' function checks the current status of the service and takes appropriate actions:
# - If the service is already running, it prints a message indicating that the service is running.
# - If the service is dead, it prints a message, starts the service using 'systemctl start', and checks for errors using 'check_err'.
# - If the service does not exist, it prints a message indicating that there is nothing to start.
start_it

# Enable the specified service using the 'enable_it' function.
# The 'enable_it' function checks the boot status of the service and takes appropriate actions:
# - If the service is already enabled, it prints a message indicating that the service is enabled.
# - If the service is disabled, it prints a message, enables the service using 'systemctl enable', and checks for errors using 'check_err'.
# - If the boot status is neither 'enabled' nor 'disabled', it prints a message indicating that there is nothing to do.
enable_it


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


