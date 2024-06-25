#!/bin/bash

# Function to check if a package is installed
function check_package() {
    dpkg -l | grep -qw "$1" || sudo apt install -y "$1"
}

# Update package list and upgrade all packages
sudo apt update
sudo apt upgrade -y

# Install necessary packages
check_package apache2
check_package mysql-server
check_package unzip
check_package jq

# Allow Applications through the firewall
sudo ufw allow in "Apache"
sudo ufw allow in "OpenSSH"
sudo ufw allow 80
sudo ufw enable
sudo ufw status

# Function to modify sshd_config to disable PasswordAuthentication
disable_password_authentication() 
    SSHD_CONFIG="/etc/ssh/sshd_config"

    # Backup the sshd_config file
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

    # Uncomment PasswordAuthentication line and set it to no
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"

    # Restart sshd service
    if command -v systemctl &> /dev/null
    then
        systemctl restart sshd
    else
        service sshd restart
    fi

    echo "Password authentication for SSH has been disabled and sshd service restarted."


# Prompt user for action
read -p "Do you want to disable password authentication for SSH (yes/no)? " user_input

case "$user_input" in
    yes|Yes|YES)
        disable_password_authentication
        ;;
    no|No|NO)
        echo "No changes made to SSH configuration."
        ;;
    *)
        echo "Invalid input. No changes made to SSH configuration."
        ;;
esac

# Install fail2ban
check_package fail2ban || echo "Failed to install fail2ban. Exiting." && exit 1

# Copy default jail.conf to jail.local
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || echo "Failed to copy jail.conf to jail.local. Exiting." && exit 1

# Backup the original jail.local file
sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak || echo "Failed to backup jail.local. Exiting." && exit 1

# Edit the jail.local configuration
sudo sed -i 's/^ignoreip = .*/ignoreip = 127.0.0.1/' /etc/fail2ban/jail.local || echo "Failed to update ignoreip in jail.local. Exiting." && exit 1
sudo sed -i 's/^bantime  = .*/bantime  = 3600/' /etc/fail2ban/jail.local || echo "Failed to update bantime in jail.local. Exiting." && exit 1
sudo sed -i 's/^findtime = .*/findtime = 600/' /etc/fail2ban/jail.local || echo "Failed to update findtime in jail.local. Exiting." && exit 1
sudo sed -i 's/^maxretry = .*/maxretry = 3/' /etc/fail2ban/jail.local || echo "Failed to update maxretry in jail.local. Exiting." && exit 1

# Restart the Fail2Ban service to apply changes
sudo systemctl restart fail2ban || echo "Failed to restart fail2ban. Exiting." && exit 1

# Enable Fail2Ban to start on boot
sudo systemctl enable fail2ban || echo "Failed to enable fail2ban on boot. Exiting." && exit 1

# Output success message
echo "Fail2Ban installation and configuration complete."

# Secure MySQL installation. Hint: password
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'password';"

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

# Detect installed PHP version
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
php_ini="/etc/php/$php_version/apache2/php.ini"

# Install PHP and necessary extensions
sudo apt install -y php libapache2-mod-php php-mysql php-gmp php-curl php-intl php-mbstring php-xmlrpc php-gd php-bcmath php-imap php-xml php-cli php-zip

# Detect installed PHP version
php_version=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
php_ini="/etc/php/$php_version/apache2/php.ini"

# Prompt user for PHP settings or use defaults
read -p "Enter max_execution_time (default 60): " max_execution_time
max_execution_time=${max_execution_time:-60}
read -p "Enter memory_limit (default 128M): " memory_limit
memory_limit=${memory_limit:-128M}
read -p "Enter upload_max_filesize (default 30M): " upload_max_filesize
upload_max_filesize=${upload_max_filesize:-30M}
read -p "Enter post_max_size (default 8M): " post_max_size
post_max_size=${post_max_size:-8M}
read -p "Enter timezone (default America/Chicago): " date_timezone
date_timezone=${date_timezone:-America/Chicago}

# Update PHP settings
sudo sed -i "s/^max_execution_time = .*/max_execution_time = $max_execution_time/" "$php_ini"
sudo sed -i "s/^memory_limit = .*/memory_limit = $memory_limit/" "$php_ini"
sudo sed -i "s/^upload_max_filesize = .*/upload_max_filesize = $upload_max_filesize/" "$php_ini"
sudo sed -i "s/^post_max_size = .*/post_max_size = $post_max_size/" "$php_ini"
sudo sed -i "s~^;date.timezone =.*~date.timezone = $date_timezone~" "$php_ini"

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

# Get the latest ChurchCRM release URL
latest_release_url=$(curl -s https://api.github.com/repos/ChurchCRM/CRM/releases/latest | jq -r '.assets[] | select(.name | test("zip$")) | .browser_download_url')

# Download and extract ChurchCRM
sudo wget "$latest_release_url" -O ChurchCRM-latest.zip
sudo unzip ChurchCRM-latest.zip -d /var/www/

# Set permissions for ChurchCRM
sudo chown -R www-data:www-data /var/www/churchcrm/
sudo chmod -R 755 /var/www/churchcrm/

# Generate a 64-character 2FA secret key
two_fa_secret=$(tr -dc '[:alnum:]!@#$%^&*()_+-=[]{}|;:,.<>?' < /dev/urandom | head -c 64)

# Update Config.php with database credentials and 2FA secret key
config_file="/var/www/churchcrm/Include/Config.php"
sudo sed -i "s/\$sUSER = '.*';/\$sUSER = 'churchcrmuser';/" "$config_file"
sudo sed -i "s/\$sPASSWORD = '.*';/\$sPASSWORD = '$db_user_password';/" "$config_file"
sudo sed -i "s/\$sDATABASE = '.*';/\$sDATABASE = 'churchcrm';/" "$config_file"
sudo sed -i "s/\$TwoFASecretKey = '.*';/\$TwoFASecretKey = '$two_fa_secret';/" "$config_file"

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
