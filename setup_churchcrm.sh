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

# Prompt user for action
read -p "Do you want to disable password authentication for SSHD (yes/no)? " user_input

if [ "$user_input" = "yes" ] || [ "$user_input" = "Yes" ] || [ "$user_input" = "YES" ]; then
    SSHD_CONFIG="/etc/ssh/sshd_config"

    # Backup the sshd_config file
    sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

    # Uncomment PasswordAuthentication line and set it to no
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"

    # Restart sshd service
    if command -v systemctl &> /dev/null; then
        if systemctl restart sshd 2>/dev/null; then
            echo "Password authentication for SSHD has been disabled and sshd service restarted."
        elif systemctl restart ssh 2>/dev/null; then
            echo "Password authentication for SSHD has been disabled and ssh service restarted."
        else
            echo "Failed to restart SSH service. Please check the service name."
        fi
    else
        if service sshd restart 2>/dev/null; then
            echo "Password authentication for SSHD has been disabled and sshd service restarted."
        elif service ssh restart 2>/dev/null; then
            echo "Password authentication for SSHD has been disabled and ssh service restarted."
        else
            echo "Failed to restart SSHD service. Please check the service name."
        fi
    fi
elif [ "$user_input" = "no" ] || [ "$user_input" = "No" ] || [ "$user_input" = "NO" ]; then
    echo "No changes made to SSHD configuration."
else
    echo "Invalid input. No changes made to SSHD configuration."
fi

#!/bin/bash

# Function to check if a package is installed
function check_package() {
    dpkg -s "$1" >/dev/null 2>&1 || sudo apt install -y "$1"
}

# Function to prompt user for input with a default value
function prompt_input() {
    read -p "$1 (default: $2): " input
    echo "${input:-$2}"  # Use input if provided, otherwise default to $2
}

# Function to add a setting if it doesn't exist in a file
function add_setting_if_not_exists() {
    local file="$1"
    local setting="$2"
    local value="$3"

    if ! grep -q "^$setting = " "$file"; then
        echo "$setting = $value" | sudo tee -a "$file" >/dev/null
    fi
}

# Install fail2ban if not already installed
check_package fail2ban || { echo "Failed to install fail2ban. Exiting."; exit 1; }

# Copy default jail.conf to jail.local
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local || { echo "Failed to copy jail.conf to jail.local. Exiting."; exit 1; }
echo "Copied jail.conf to jail.local"

# Backup the original jail.local file
sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak || { echo "Failed to backup jail.local. Exiting."; exit 1; }
echo "Backed up jail.local to jail.local.bak"

# Prompt user for Fail2ban settings
bantime=$(prompt_input "Enter bantime in seconds" "3600")
findtime=$(prompt_input "Enter findtime in seconds or minutes (e.g., 10m for 10 minutes)" "10m")
maxretry=$(prompt_input "Enter maxretry" "3")
ignoreip=$(prompt_input "Enter ignoreip (default: 127.0.0.1)" "127.0.0.1")

# Update the jail.local configuration with user inputs
sudo sed -i "s/^bantime  = .*/bantime  = $bantime/" /etc/fail2ban/jail.local || { echo "Failed to update bantime in jail.local. Exiting."; exit 1; }
echo "Updated bantime in jail.local"
sudo sed -i "s/^findtime  = .*/findtime  = $findtime/" /etc/fail2ban/jail.local || { echo "Failed to update findtime in jail.local. Exiting."; exit 1; }
echo "Updated findtime in jail.local"
sudo sed -i "s/^maxretry = .*/maxretry = $maxretry/" /etc/fail2ban/jail.local || { echo "Failed to update maxretry in jail.local. Exiting."; exit 1; }
echo "Updated maxretry in jail.local"

# Add ignoreip setting if it doesn't exist
add_setting_if_not_exists "/etc/fail2ban/jail.local" "ignoreip" "$ignoreip"
echo "Added ignoreip setting to jail.local if it didn't exist"

echo "Fail2Ban installation and configuration completed successfully."


# Check if script is being run with sudo/root privileges
if [ "$(id -u)" -ne 0 ]; then
    # Re-run this script with sudo if not already running as root
    sudo "$0" "$@"
    exit $?
fi

# Function to securely prompt for MySQL root password
prompt_for_password() {
    while true; do
        read -s -p "Enter MySQL root password (or press Enter if none): " mysql_root_password
        echo
        read -s -p "Confirm MySQL root password: " mysql_root_password_confirm
        echo
        [ "$mysql_root_password" = "$mysql_root_password_confirm" ] && break
        echo "Passwords do not match. Please try again."
    done
}

# Install MySQL Server
echo "Installing MySQL Server..."
apt update
apt install -y mysql-server

# Run mysql_secure_installation script
echo "Running mysql_secure_installation..."

# Prompt user for MySQL root password
prompt_for_password

# Here we use a heredoc to provide input to the mysql_secure_installation script non-interactively
mysql_secure_installation <<EOF

y
$mysql_root_password
$mysql_root_password
y
y
y
y
EOF

echo "MySQL installation and secure setup completed."

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
