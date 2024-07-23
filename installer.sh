#!/bin/bash

random_string() {
    local length=8
    local chars="a-zA-Z0-9"
    local rstring

    # Generate a random string with the specified length
    rstring=$(head /dev/urandom | tr -dc "$chars" | head -c "$length")
    
    echo "${rstring}"
}


server_ipv4(){
    ivp4_temp=$(curl -s ipv4.icanhazip.com)
    echo $ivp4_temp
}

get_app_url(){
    ipv4=$(server_ipv4);
    echo "http://$ipv4"
}

disable_needrestart() {
    local nrconf_file="/etc/needrestart/needrestart.conf"
    
    if [ -e "$nrconf_file" ]; then
        echo '$nrconf{restart} = "a";' >> "$nrconf_file"
    fi
}

# Function to update and upgrade the system
update_system() {
    echo "Updating system packages..."
    sudo apt update -y && sudo apt upgrade -y
}

install_packages() {
    echo "Installing PHP 8.1..."
    sudo apt install -y zip unzip net-tools curl cron
    sudo apt install -y lsb-release ca-certificates apt-transport-https software-properties-common

    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update -y
    sudo apt install -y mariadb-server php8.1 php8.1-fpm php8.1-cli php8.1-mysql 
    sudo apt install -y php8.1-common php8.1-opcache php8.1-mbstring php8.1-zip php8.1-intl php8.1-simplexml php8.1-curl
    sudo apt install -y nginx

    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    sudo systemctl restart mariadb

nx
}

# Function to install PHP SSH2 extension
install_php_ssh2() {
    echo "Installing PHP SSH2 extension..."
    sudo apt install -y libssh2-1-dev
    sudo apt install -y php-pear php8.1-dev
    yes | sudo pecl install ssh2
    echo "extension=ssh2.so" | sudo tee /etc/php/8.1/mods-available/ssh2.ini
    sudo ln -s /etc/php/8.1/mods-available/ssh2.ini /etc/php/8.1/fpm/conf.d/20-ssh2.ini
    sudo ln -s /etc/php/8.1/mods-available/ssh2.ini /etc/php/8.1/cli/conf.d/20-ssh2.ini
    sudo systemctl restart php8.1-fpm
}

# Function to create a self-signed SSL certificate (for testing)
create_self_signed_cert() {
    echo "Creating a self-signed SSL certificate..."
    sudo mkdir -p /etc/ssl/private
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=rocket.app"
}

configure_nginx() {
    echo "Configuring Nginx..."
    rm /etc/nginx/sites-available/default
    rm /etc/nginx/sites-enabled/default

    sudo tee /etc/nginx/sites-available/rocket <<'EOF'
server {
    listen 80;
    server_name rocket.app;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param PHP_VALUE "memory_limit=4096M";
        fastcgi_param IONCUBE "/usr/local/ioncube/ioncube_loader_lin_8.1.so";
        fastcgi_param PHP_ADMIN_VALUE "zend_extension=/usr/local/ioncube/ioncube_loader_lin_8.1.so";
    }

    location ~ /\.ht {
        deny all;
    }
}

EOF
    sudo ln -s /etc/nginx/sites-available/rocket /etc/nginx/sites-enabled/
    sudo rm  /var/www/html/index.nginx-debian.html 

    sudo systemctl start nginx
    sudo systemctl enable nginx

    sudo nginx -t
    sudo systemctl reload nginx
}

# Function to install ionCube Loader
install_ioncube() {

    echo "Installing ionCube Loader..."
    sed -i 's@zend_extension = /usr/local/ioncube/ioncube_loader_lin_8.1.so@@' /etc/php/8.1/cli/php.ini

    uname=$(uname -i)
    if [[ $uname == x86_64 ]]; then
        wget -4 https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
        sudo tar xzf ioncube_loaders_lin_x86-64.tar.gz -C /usr/local
        sudo rm -rf ioncube_loaders_lin_x86-64.tar.gz
    fi
    if [[ $uname == aarch64 ]]; then
        wget -4 https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_aarch64.tar.gz
        sudo tar xzf ioncube_loaders_lin_aarch64.tar.gz -C /usr/local
        sudo rm -rf ioncube_loaders_lin_aarch64.tar.gz
    fi
    PHPVERSION=$(php -v | grep -oP '^PHP \K[0-9]+\.[0-9]+')

    echo "zend_extension = /usr/local/ioncube/ioncube_loader_lin_${PHPVERSION}.so" > /etc/php/${PHPVERSION}/fpm/conf.d/00-ioncube.ini
    echo "zend_extension = /usr/local/ioncube/ioncube_loader_lin_${PHPVERSION}.so" > /etc/php/${PHPVERSION}/cli/conf.d/00-ioncube.ini

    PHP_INI_PATH="/etc/php/8.1/fpm/php.ini"
    ZEND_EXTENSION_PATH="/usr/local/ioncube/ioncube_loader_lin_8.1.so"
    grep -q "^zend_extension" $PHP_INI_PATH && sed -i "s@^zend_extension.*@zend_extension = $ZEND_EXTENSION_PATH@" $PHP_INI_PATH || echo "zend_extension = $ZEND_EXTENSION_PATH" >> $PHP_INI_PATH
    sudo systemctl restart php8.1-fpm
    systemctl restart nginx
}

setup_project_files() {
    APP_LINK="https://api.github.com/repos/rocket-ap/rocket-pro/releases/latest"
    APP_LINK=$(sudo curl -Ls "$APP_LINK" | grep '"browser_download_url":' | sed -E 's/.*"([^"]+)".*/\1/')

    ZIP_PATH="/var/www/html/app.zip"
  
    sudo wget -O $ZIP_PATH $APP_LINK
    wait
    sudo unzip -o $ZIP_PATH -d /var/www/html

    sudo chown -R www-data:www-data /var/www/html
    chown www-data:www-data /var/www/html/index.php
    echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/mysqldump' | sudo EDITOR='tee -a' visudo &
    wait
    echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/zip' | sudo EDITOR='tee -a' visudo &
    wait
    echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/zip -r' | sudo EDITOR='tee -a' visudo &
    wait

    rm $ZIP_PATH
}

configure_database() {
    DB_NAME="rocket_app"
    DB_PREFIX="rs_"
    
    echo "Configuring MySQL database..."
    
    mysql -e "create database $DB_NAME;" &
    wait
    mysql -e "CREATE USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';" &
    wait
    mysql -e "GRANT ALL ON *.* TO '${USERNAME}'@'localhost';" &\
    wait
    mysql -e "ALTER USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';"&
    wait

    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/g" /var/www/html/.env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$USERNAME/g" /var/www/html/.env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$PASSWORD/g" /var/www/html/.env

    USERS_TABLE="${dbPrefix}admins"
    MYSQL_CMD="mysql -u'$USERNAME' -p'$PASSWORD' -e 'USE $DB_NAME; SHOW TABLES LIKE \"$USERS_TABLE\";'"

    if eval "$MYSQL_CMD" | grep -q "$USERS_TABLE"; then 

        mysql -e "USE ${DB_NAME}; UPDATE ${USERS_TABLE} SET username = '${USERNAME}' where id='1';"
        mysql -e "USE ${DB_NAME}; UPDATE ${USERS_TABLE} SET password = '${USERNAME}' where id='1';"

    else

        DB_PATH="/var/www/html/assets/db.sql"
        mysql -u ${USERNAME} --password=${PASSWORD} ${DB_NAME} < $DB_PATH

        PHP_PASSWORD=$(php -r "echo password_hash('$PASSWORD', PASSWORD_BCRYPT);")
        CTIME=$(php -r "echo time();")

        INSERT_VALUES=" '${USERNAME}', '${PHP_PASSWORD}', 'modir', '', 'admin', '0', '0', 'active', '', '', '0', '${CTIME}', '0', '0' ";
        INSERT_SQL="INSERT INTO rs_users(username, password, full_name, mobile, role, credit, unlimited, \`status\`, status_desc, \`desc\`, cid, ctime, uid, utime) VALUES ($INSERT_VALUES)";

        mysql -e "USE ${DB_NAME}; ${INSERT_SQL};"
    
    fi

}

# Function to create a cronjob for application
configure_crontab(){

    ipv4=$(server_ipv4)
    (crontab -l ; echo "* * * * * wget -q -O /dev/null 'http://${ipv4}/cron/master' > /dev/null 2>&1") | crontab -
}

# Function to check installation
check_installation() {
    echo "Verifying installation..."

    # Check PHP installation
    php_version=$(php -v | grep -o "PHP 8.1")
    if [ -z "$php_version" ]; then
        echo "PHP 8.1 installation failed."
    else
        echo "PHP 8.1 installed successfully."
    fi

    # Check PHP SSH2 extension
    ssh2_extension=$(php -m | grep ssh2)
    if [ -z "$ssh2_extension" ]; then
        echo "PHP SSH2 extension installation failed."
    else
        echo "PHP SSH2 extension installed successfully."
    fi

    # Check MariaDB installation
    mariadb_status=$(systemctl is-active mariadb)
    if [ "$mariadb_status" != "active" ]; then
        echo "MariaDB installation failed."
    else
        echo "MariaDB installed and running."
    fi

    # Check MySQL installation
    mysql_status=$(systemctl is-active mysql)
    if [ "$mysql_status" != "active" ]; then
        echo "MySQL installation failed."
    else
        echo "MySQL installed and running."
    fi

    # Check Nginx installation
    nginx_status=$(systemctl is-active nginx)
    if [ "$nginx_status" != "active" ]; then
        echo "Nginx installation failed."
    else
        echo "Nginx installed and running."
    fi

    echo "Verification complete."
}


# Main function to run all steps
main() {

    USERNAME=$(random_string)
    PASSWORD=$(random_string)

    disable_needrestart
    update_system
    install_packages
    install_php_ssh2
    create_self_signed_cert
    configure_nginx
    install_ioncube
    setup_project_files
    configure_database
    check_installation
    configure_crontab

    ipv4=$(server_ipv4)

    clear
    echo -e "\n"

    printf "\nPanel Link : http://${ipv4}/admin/login"
    printf "\nUsername : \e[31m${USERNAME}\e[0m "
    printf "\nPassword : \e[31m${PASSWORD}\e[0m \n"
}

# Execute main function
main
