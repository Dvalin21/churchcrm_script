#!/bin/bash

# Function to check if a package is installed
function check_package() {
    dpkg -l | grep -qw "$1" || sudo apt install -y "$1"
}

# Function to prompt user input with default values
function prompt_with_default() {
    local prompt="$1"
    local default="$2"
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

# Update package list and upgrade all packages
sudo apt update
sudo apt upgrade -y

# Install necessary packages
check_package apache2
check_package mysql-server
check_package unzip
check_package jq

# Allow Apache through the firewall
sudo ufw allow in "Apache"
sudo ufw status

# Secure MySQL installation
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';"

# Prompt user for MySQL root password and new password
current_mysql_password=$(prompt_with_default "Enter current MySQL root password (leave empty if not set)" "")
new_mysql_password=$(prompt_with_default "Enter new MySQL root password" "password")
confirm_mysql_password=$(prompt_with_default "Confirm new MySQL root password" "password")

# Check if the new passwords match
if [ "$new_mysql_password" != "$confirm_mysql_password" ]; then
    echo "Passwords do not match. Exiting."
    exit 1
fi

# Run mysql_secure_installation with user inputs
sudo mysql_secure_installation <<EOF

$current_mysql_password
y
$new_mysql_password
$new_mysql_password
y
y
y
y
EOF

# Detect installed PHP version
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
php_ini="/etc/php/$php_version/apache2/php.ini"

# Install PHP and necessary extensions
sudo apt install -y "php$php_version" "libapache2-mod-php$php_version" "php${php_version}-mysql" "php${php_version}-gmp" "php${php_version}-curl" "php${php_version}-intl" "php${php_version}-mbstring" "php${php_version}-xmlrpc" "php${php_version}-gd" "php${php_version}-bcmath" "php${php_version}-imap" "php${php_version}-xml" "php${php_version}-cli" "php${php_version}-zip"

# Prompt user for PHP settings or use defaults
max_execution_time=$(prompt_with_default "Enter max_execution_time" "30")
memory_limit=$(prompt_with_default "Enter memory_limit" "128M")
upload_max_filesize=$(prompt_with_default "Enter upload_max_filesize" "2M")
post_max_size=$(prompt_with_default "Enter post_max_size" "8M")
date_timezone=$(prompt_with_default "Enter date.timezone" "UTC")

# Update PHP settings
sudo sed -i "s/^max_execution_time = .*/max_execution_time = $max_execution_time/" "$php_ini"
sudo sed -i "s/^memory_limit = .*/memory_limit = $memory_limit/" "$php_ini"
sudo sed -i "s/^upload_max_filesize = .*/upload_max_filesize = $upload_max_filesize/" "$php_ini"
sudo sed -i "s/^post_max_size = .*/post_max_size = $post_max_size/" "$php_ini"
sudo sed -i "s~^;date.timezone =.*~date.timezone = $date_timezone~" "$php_ini"

# Enable the correct PHP module
sudo a2enmod "php$php_version"
sudo systemctl restart apache2

# Restart Apache to apply changes
sudo systemctl restart apache2

# Prompt user for new database user password
db_user_password=$(prompt_with_default "Enter password for new database user 'churchcrmuser'" "password")

# Create MySQL database and user
sudo mysql -u root -p"$new_mysql_password" <<EOF
CREATE DATABASE churchcrm;
CREATE USER 'churchcrmuser'@'localhost' IDENTIFIED BY '$db_user_password';
GRANT ALL ON churchcrm.* TO 'churchcrmuser'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
EOF

# Get the latest ChurchCRM release URL
latest_release_url=$(curl -s https://api.github.com/repos/ChurchCRM/CRM/releases/latest | jq -r '.assets[] | select(.name | test("zip$")) | .browser_download_url')

# Download and extract ChurchCRM
sudo wget "$latest_release_url" -O ChurchCRM-latest.zip
sudo unzip ChurchCRM-latest.zip -d /var/www/

# Set permissions for ChurchCRM
sudo chown -R www-data:www-data /var/www/churchcrm/
sudo chmod -R 755 /var/www/churchcrm/

# Prompt user for Apache configuration details
server_admin=$(prompt_with_default "Enter ServerAdmin email" "admin@example.com")
server_name=$(prompt_with_default "Enter ServerName" "example.com")
server_alias=$(prompt_with_default "Enter ServerAlias" "www.example.com")

# Create Apache configuration file for ChurchCRM
sudo bash -c "cat <<EOF > /etc/apache2/sites-available/churchcrm.conf
<VirtualHost *:80>
    ServerAdmin $server_admin
    DocumentRoot /var/www/churchcrm
    ServerName $server_name
    ServerAlias $server_alias

    <Directory /var/www/churchcrm/>
        Options FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"

# Enable the ChurchCRM site and rewrite module
sudo a2ensite churchcrm.conf
sudo a2enmod rewrite
sudo systemctl restart apache2

# Update DirectoryIndex to prioritize index.php
sudo sed -i '/<IfModule mod_dir.c>/,/<\/IfModule>/c\<IfModule mod_dir.c>\n    DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm\n<\/IfModule>' /etc/apache2/mods-enabled/dir.conf

# Restart Apache to apply the configuration changes
sudo systemctl restart apache2

# Output all new passwords
echo "Installation and configuration complete. Visit your server's URL to complete the ChurchCRM setup."
echo "Initial login credentials for ChurchCRM:"
echo "Username: Admin"
echo "Password: changeme"
echo
echo "New passwords:"
echo "MySQL root password: $new_mysql_password"
echo "ChurchCRM database name: churchcrm"
echo "ChurchCRM database username: churchcrmuser"
echo "ChurchCRM database user password: $db_user_password"
