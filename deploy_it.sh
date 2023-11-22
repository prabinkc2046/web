#!/bin/bash

# This script is intended to run on Ubuntu 22.04
# This script needs to be run with sudo
# This script takes 3 arguments: <package name> <service name> <site name>
# This script should be run as sudo, for example: sudo ./script.sh <package name> <service name> <site name>
# The server_name_or_ip variable can be either an IP or domain name.
# If an IP is used, it may result in an error on the second run due to a duplicate error. Use a domain name if available.


# Global arguments
package_name=$1
service=$2
site_name=$3
github_repo=$4
server_name_or_ip=$(curl ipinfo.io/ip)

# Check if the required number of arguments is provided or not
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <package name> <service name> <site name> <github_repo>"
    echo "sudo ./deploy_it.sh nginx nginx mynewwebsite /web"
    exit 3
fi



# Check if the provided github link is valid
get_repo(){
http_status=$(curl -s -o /dev/null -w "%{http_code}" -L "$github_repo")
if [ "http_status" -ne 200 ]; then
    echo "Http response from the git repo is not 200. Provide the correct link for your repo. Exiting.."
    exit 4
else
    repo=$(echo "$github_repo" | awk -F/ '{print $NF}' | awk -F"." '{if (NF == 2){ print $(NF -1)} else if(NF == 3){print $(NF - 2)"."$(NF -1)} else if (NF == 4) {print $(NF -3)"."$(NF - 2)"."$(NF -1)} else {print"Your repo name contains more than 3 words separted by '.' this script can parse the repo name when it is less than or equal to 3 "}}')
fi
}
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
        echo "
        $command was successful.
        "
    else
        echo "
        Error while $command. Exiting
        "
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
    echo "the value of install is: $package_present"

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
    service_status=$(systemctl status $service | grep -i "active" | awk '{print $3}')

    # Case statement to handle different service statuses
    case $service_status in
        "(running)")
        echo "
        $service is running.
        "
        ;;
        "(dead)")
        echo "
        $service is dead. Starting $service now...
        "
        systemctl start $service
        check_err "systemctl start $service" "$?"
        ;;
        *)
        echo "
        $service does not exist. No need to start this service.
        "
        ;;
    esac
}


# Function to check and enable a service if it is currently disabled
# Usage: enable_it
# - The function retrieves the boot status of the specified service using systemctl.
# - If the service is already "enabled," it prints a message indicating that the service is already enabled.
# - If the service is "disabled," it prints a message, enables the service using systemctl, and checks for errors using check_err.
# - If the boot status is neither "enabled" nor "disabled," it prints a message indicating that there is nothing to do.
enable_it(){
    # Get the boot status of the service
    boot_status=$(systemctl status $service | grep -i "loaded" | awk -F";" '{print $2}')

    # Case statement to handle different service boot statuses
    case "$boot_status" in
        "enabled")
        echo "
        $service is enabled.
        "
        ;;
        "disabled")
        echo "
        $service is disabled. Enabling it now...
        "
        systemctl enable $service
        check_err "systemctl enable $service" "$?"
        ;;
        *)
        echo "Nothing to do. Skipping..."
        ;;
    esac
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
    path_to_default_site_dir=$(find / -type d -name "www")

    # Check if the site directory already exists
    if [ -d "$path_to_default_site_dir/$site_name" ]; then
        echo "$site_name already exists. Try another name. Exiting..."
        exit 2
    else
        # Create the site directory
        mkdir "$path_to_default_site_dir/$site_name"
        path_to_new_site=$(find "$path_to_default_site_dir" -type d -name "$site_name")
        echo "$path_to_new_site is created."

        # Assign ownership and set permissions for the nginx user
        echo "Assigning ownership and permission to $nginx_user"
        chown "$nginx_user":"$nginx_user" -R "$path_to_new_site"
        chmod 770 -R "$path_to_new_site"
    fi
}

# Function to remove the default Nginx site configuration
# Usage: remove_default
# - Checks if the default configuration file in /etc/nginx/sites-available exists.
# - If it exists, it renames the file to default.bak.
# - Checks if the default configuration file in /etc/nginx/sites-enabled exists.
# - If it exists, it removes the file to disable the default site.
remove_default(){
    # Check if the default configuration file in sites-available exists
    if [ -f /etc/nginx/sites-available/default ]; then
        # Rename the default configuration file to default.bak
        mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    fi

    # Check if the default configuration file in sites-enabled exists
    if [ -f /etc/nginx/sites-enabled/default ]; then
        # Remove the default configuration file to disable the default site
        rm /etc/nginx/sites-enabled/default
    fi
}



# Function to configure a new Nginx site
# Usage: configure_site
# - Calls remove_default to ensure the default Nginx site is removed.
# - Creates a new configuration file for the specified site in /etc/nginx/sites-available.
# - The configuration includes basic server settings, such as root directory, index files, server name or IP, and location settings.
# - Creates a symbolic link in /etc/nginx/sites-enabled to enable the new site.
configure_site(){
    # Call remove_default to remove the default Nginx site configuration
    remove_default

    # Create a new configuration file for the site in sites-available
    touch /etc/nginx/sites-available/$site_name
    cat > /etc/nginx/sites-available/$site_name << EOF
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root "$path_to_new_site";

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;
        server_name "$server_name_or_ip";
        location / {
            # First attempt to serve request as file, then
            # as directory, then fall back to displaying a 404.
            try_files \$uri \$uri/ =404;
        }
    }
EOF

    # Create a symbolic link to enable the new site
    ln -s /etc/nginx/sites-available/$site_name /etc/nginx/sites-enabled/
}

deploy_it(){
    echo "Pulling the source code from the given repo"
    git clone "$github_repo"
    # Display a message and change into the specified project directory
    echo "CD into the $repo"
    cd "$repo"

    # Copying all files and folders in the project directory to the specified site directory
    echo "Coping the files and folders to the $path_to_new_site"
    cp * "$path_to_new_site"

    # Restart the specified service
    echo "Restarting $service now..."
    systemctl restart $service
    check_err "systemctl restart $service" "$?"
}



# Update package information using 'apt update' with the '-y' flag for automatic confirmation.
apt update -y

# Check the exit status of the 'apt update' command using the 'check_err' function.
# The first argument is the command executed, and the second argument is its exit status.
# If the exit status is non-zero, print an error message and exit with status 1; otherwise, indicate a successful update.
check_err "apt update -y" "$?"



# Invoke the 'install_it' function with the specified package name.
# The 'install_it' function checks whether the package is already installed.
# If the package is not installed, it installs the package using 'apt install -y'.
# The 'check_err' function is used to verify the success of the installation.
install_it "$package_name"


# Start the specified service using the 'start_it' function.
# The 'start_it' function checks the current status of the service and takes appropriate actions:
# - If the service is already running, it prints a message indicating that the service is running.
# - If the service is dead, it prints a message, starts the service using 'systemctl start', and checks for errors using 'check_err'.
# - If the service does not exist, it prints a message indicating that there is nothing to start.
start_it "$service"


# Enable the specified service using the 'enable_it' function.
# The 'enable_it' function checks the boot status of the service and takes appropriate actions:
# - If the service is already enabled, it prints a message indicating that the service is enabled.
# - If the service is disabled, it prints a message, enables the service using 'systemctl enable', and checks for errors using 'check_err'.
# - If the boot status is neither 'enabled' nor 'disabled', it prints a message indicating that there is nothing to do.
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
configure_site "$site_name"


# Pull the source code from the git hub repo and CD into that repo
# Move the content of the repo into the new site directory
# Restart the nginx service
deploy_it "$github_repo"

