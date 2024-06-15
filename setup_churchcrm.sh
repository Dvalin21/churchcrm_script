#!/bin/bash

# Update package list
sudo apt update
sudo apt upgrade -y

# Install Apache
sudo apt install -y apache2

# Allow Apache through the firewall
sudo ufw allow in "Apache"
sudo ufw status

# Install MySQL
sudo apt install -y mysql-server

# Secure MySQL installation
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';"

# Prompt user for MySQL root password and new password
read -sp "Enter current MySQL root password (leave empty if not set): " current_mysql_password
echo
read -sp "Enter new MySQL root password: " new_mysql_password
echo
read -sp "Confirm new MySQL root password: " confirm_mysql_password
echo

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

# Install PHP and necessary extensions
sudo apt install -y php libapache2-mod-php php-mysql php-gmp php-curl php-intl php-mbstring php-xmlrpc php-gd php-bcmath php-imap php-xml php-cli php-zip

# Prompt user for PHP settings or use defaults if blank
read -p "Enter max_execution_time (leave blank for default 360): " max_execution_time
max_execution_time=${max_execution_time:-360}

read -p "Enter file_uploads (On/Off, leave blank for default On): " file_uploads
file_uploads=${file_uploads:-On}

read -p "Enter memory_limit (leave blank for default 256M): " memory_limit
memory_limit=${memory_limit:-256M}

read -p "Enter upload_max_filesize (leave blank for default 100M): " upload_max_filesize
upload_max_filesize=${upload_max_filesize:-100M}

read -p "Enter allow_url_fopen (On/Off, leave blank for default On): " allow_url_fopen
allow_url_fopen=${allow_url_fopen:-On}

read -p "Enter short_open_tag (On/Off, leave blank for default On): " short_open_tag
short_open_tag=${short_open_tag:-On}

read -p "Enter your timezone (e.g., America/Chicago, leave blank for default America/Chicago): " user_timezone
user_timezone=${user_timezone:-America/Chicago}

# Update PHP settings
sudo sed -i "s/max_execution_time = .*/max_execution_time = $max_execution_time/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s/file_uploads = .*/file_uploads = $file_uploads/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = $memory_limit/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = $upload_max_filesize/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s/allow_url_fopen = .*/allow_url_fopen = $allow_url_fopen/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s/short_open_tag = .*/short_open_tag = $short_open_tag/" /etc/php/8.1/apache2/php.ini
sudo sed -i "s|;date.timezone =.*|date.timezone = ${user_timezone}|" /etc/php/8.1/apache2/php.ini

# Restart Apache to apply changes
sudo systemctl restart apache2

# Prompt user for new database user password
read -sp "Enter password for new database user 'churchcrmuser': " db_user_password
echo

# Create MySQL database and user
sudo mysql -u root -p"$new_mysql_password" <<EOF
CREATE DATABASE churchcrm;
CREATE USER 'churchcrmuser'@'localhost' IDENTIFIED BY '$db_user_password';
GRANT ALL ON churchcrm.* TO 'churchcrmuser'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
EOF

# Install jq for processing JSON
sudo apt install -y jq

# Get the latest ChurchCRM release URL
latest_release_url=$(curl -s https://api.github.com/repos/ChurchCRM/CRM/releases/latest | jq -r '.assets[] | select(.name | test("zip$")) | .browser_download_url')

# Download and extract ChurchCRM
sudo wget "$latest_release_url" -O ChurchCRM-latest.zip
sudo apt install -y unzip
sudo unzip ChurchCRM-latest.zip -d /var/www/
sudo mv /var/www/churchcrm /var/www/churchcrm

# Set permissions for ChurchCRM
sudo chown -R www-data:www-data /var/www/churchcrm/
sudo chmod -R 755 /var/www/churchcrm/

# Prompt user for Apache configuration details
read -p "Enter ServerAdmin email (e.g., admin@example.com): " server_admin
read -p "Enter ServerName (e.g., example.com): " server_name
read -p "Enter ServerAlias (e.g., www.example.com): " server_alias

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

     ErrorLog \${APACHE_LOG_DIR}/error.log
     CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"

# Enable the ChurchCRM site and rewrite module
sudo a2ensite churchcrm.conf
sudo a2enmod rewrite
sudo a2dissite 000-default.conf
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
