#!/bin/bash
# Risky script example - installs software and modifies system

# Download and execute remote script (HIGH RISK!)
curl -sSL https://example.com/install.sh | bash

# Install packages
sudo apt-get update
sudo apt-get install -y nginx mysql-server

# Modify system configuration
sudo chmod 777 /var/www/html
sudo echo "server { ... }" > /etc/nginx/nginx.conf

# Create cron job
echo "0 2 * * * /usr/bin/backup.sh" | crontab -

# Add to shell profile
echo "export PATH=$PATH:/opt/custom/bin" >> ~/.bashrc

# Download file
wget https://example.com/data.tar.gz
tar -xzf data.tar.gz
rm -rf /tmp/old_data

# Start services
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Installation complete!"
