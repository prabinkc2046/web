#!/bin/bash

# This script is intended to run on Ubuntu 22.04
# This script needs to be run with sudo
# This script takes 3 arguments: <package name> <service name> <site name>
# This script should be run as sudo, for example: sudo ./script.sh <package name> <service name> <site name>
# The server_name_or_ip variable can be either an IP or domain name.
# If an IP is used, it may result in an error on the second run due to a duplicate error. Use a domain name if available.

# Check if the required number of arguments is provided or not
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <package name> <service name> <site name>"
    exit 3
fi

# Global arguments
package_name=$1
service=$2
site_name=$3
server_name_or_ip=$(curl ipinfo.io/ip)

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

install_it(){
    installed=$(dpkg -l | awk '{print $2}' | awk '{for(i=1; i<=NF; i++) {if($i == "$package_name") {print "true"}}}')
    if $installed; then
        echo "$package_name is already installed. Skipping installation..."
    else
        echo "
        $package_name is not installed. Installing now...
        "
        apt install -y "$package_name"
        check_err "apt install -y $package_name" "$?"
    fi
}

# Start the service if it is not started
# Grab the line that has the word 'active' and grab the 3rd field of this line
start_it(){
    service_status=$(systemctl status $service | grep -i "active" | awk '{print $3}')
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

enable_it(){
    boot_status=$(systemctl status $service | grep -i "loaded" | awk -F";" '{print $2}')
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

# Find the path to the nginx.conf file
# Find the user of nginx
# Find the path to the default site directory
# Create a site directory in the default site directory
# Provide ownership and permission to the new site directory
create_site(){
    path_to_config_file=$(find / -type f -name "nginx.conf")
    nginx_user=$(cat "$path_to_config_file" | awk '/user/{print $2}')
    nginx_user=$(echo "$nginx_user" | sed 's/;$//')
    path_to_default_site_dir=$(find / -type d -name "www")
    if [ -d $path_to_default_site_dir/$site_name ]; then
        echo "$site_name already exists. Try another name. Exiting..."
        exit 2
    else
        mkdir "$path_to_default_site_dir/$site_name"
        path_to_new_site=$(find "$path_to_default_site_dir" -type d -name "$site_name")
        echo "$path_to_new_site is created."
        echo "Assigning ownership and permission to $nginx_user"
        chown "$nginx_user":"$nginx_user" -R "$path_to_new_site"
        chmod 770 -R "$path_to_new_site"
    fi
}

configure_site(){
    if [ -f /etc/nginx/sites-available/default ]; then
        mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    fi
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
    ln -s /etc/nginx/sites-available/$site_name /etc/nginx/sites-enabled/
}

# Update
apt update -y
check_err "apt update -y" "$?"

# Checks if the given software is already installed
# Installs it if it is not installed
# Skips if it is already installed
install_it "$package_name"

# Start the service
start_it "$service"

# Enable
enable_it "$service"


#create site
create_site "$site_name"

# Configure the site
configure_site "$site_name"

# copying
cp ./code/* "$path_to_new_site"
systemctl restart $service
check_err "systemctl restart $service" "$?"
