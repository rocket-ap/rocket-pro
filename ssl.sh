#!/bin/bash
read -rp "Please enter the pointed domain / sub-domain name: " domain
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d $domain

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

server {
    listen 443 ssl;
    server_name rocket.app;

    root /var/www/html;
    index index.php index.html index.htm;

    ssl_certificate /etc/letsencrypt/live/newdomain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/newdomain/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

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

sed -i "s/newdomain/$domain/g" /etc/nginx/sites-available/rocket
sudo ln -s /etc/nginx/sites-available/rocket /etc/nginx/sites-enabled/

sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl reload nginx

clear
printf "\nHTTPS Address : https://${domain}/ \n"
