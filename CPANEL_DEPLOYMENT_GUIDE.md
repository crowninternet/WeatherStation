# Weather Station App - cPanel/WHM Deployment Guide

## Overview
This guide will help you deploy the Weather Station app on port 80 in a cPanel environment created through WHM. We'll set up a Node.js application with proper process management and port configuration.

## Prerequisites
- WHM access to create cPanel accounts
- Node.js installed on the server
- SSH access to the server
- Domain name pointing to the server

## Step 1: Create cPanel Account via WHM

### 1.1 Access WHM
1. Log into WHM at `https://your-server-ip:2087`
2. Navigate to **Account Functions** → **Create a New Account**

### 1.2 Configure Account Settings
```
Domain: weatherstation.com
Username: weatheruser
Password: [strong password]
Email: admin@weatherstation.com
Package: [select appropriate package]
```

### 1.3 Verify Account Creation
- Account should be created successfully
- Note the account's home directory (usually `/home/weatheruser`)

## Step 2: Server Preparation

### 2.1 Install Node.js (if not already installed)
```bash
# On CentOS/RHEL
sudo yum install -y nodejs npm

# On Ubuntu/Debian
sudo apt update
sudo apt install -y nodejs npm

# Verify installation
node --version
npm --version
```

### 2.2 Configure Firewall
```bash
# Allow port 80
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# Or for UFW (Ubuntu)
sudo ufw allow 80/tcp
```

## Step 3: Deploy Application to cPanel Account

### 3.1 Upload Application Files
```bash
# SSH into the server as root or with sudo access
ssh root@your-server-ip

# Navigate to the cPanel account's public_html
cd /home/weatheruser/public_html

# Clone or upload the application
git clone https://github.com/your-repo/WeatherStation.git .
# OR upload files via cPanel File Manager
```

### 3.2 Install Dependencies
```bash
cd /home/weatheruser/public_html
npm install --production
```

### 3.3 Create Environment Configuration
```bash
# Create .env file
cat > .env << 'EOF'
# AmbientWeather API Configuration
AMBIENT_API_KEY=your_api_key_here
AMBIENT_APP_KEY=your_application_key_here

# Server configuration
PORT=80
NODE_ENV=production

# Optional: Specific station MAC addresses
STATION_MACS=

# Optional: Admin token for protected endpoints
ADMIN_TOKEN=your_secure_token_here

# Optional: Data ingestion limits
INGEST_LIMIT=200

# Optional: Timezone
TIMEZONE=America/New_York
EOF
```

## Step 4: Configure Process Management

### 4.1 Create Process Management Script
```bash
# Create startup script
cat > /home/weatheruser/public_html/start-server.sh << 'EOF'
#!/bin/bash

# Weather Station Server Startup Script for cPanel
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_FILE="$SCRIPT_DIR/server.js"
LOG_FILE="$SCRIPT_DIR/server.log"
PID_FILE="$SCRIPT_DIR/server.pid"

# Function to check if server is running
is_server_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Function to start the server
start_server() {
    echo "$(date): Starting Weather Station Server on port 80..." >> "$LOG_FILE"
    cd "$SCRIPT_DIR"
    
    # Kill any existing processes on port 80
    lsof -ti:80 | xargs kill -9 2>/dev/null || true
    
    # Start the server as the cPanel user
    nohup node "$SERVER_FILE" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    echo "$(date): Server started with PID $pid" >> "$LOG_FILE"
    echo "Server started with PID $pid"
}

# Function to stop the server
stop_server() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        echo "$(date): Stopping server (PID $pid)..." >> "$LOG_FILE"
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "$(date): Server stopped" >> "$LOG_FILE"
    fi
}

# Function to restart the server
restart_server() {
    echo "$(date): Restarting server..." >> "$LOG_FILE"
    stop_server
    sleep 2
    start_server
}

# Main script logic
case "$1" in
    start)
        if is_server_running; then
            echo "Server is already running"
        else
            start_server
        fi
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        if is_server_running; then
            pid=$(cat "$PID_FILE")
            echo "Server is running (PID: $pid)"
        else
            echo "Server is not running"
        fi
        ;;
    monitor)
        echo "Starting server monitor..."
        while true; do
            if ! is_server_running; then
                echo "$(date): Server not running, restarting..." >> "$LOG_FILE"
                start_server
            fi
            sleep 30
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|monitor}"
        exit 1
        ;;
esac
EOF

# Make script executable
chmod +x /home/weatheruser/public_html/start-server.sh
```

### 4.2 Create Systemd Service (Recommended)
```bash
# Create systemd service file
sudo cat > /etc/systemd/system/weatherstation.service << 'EOF'
[Unit]
Description=Weather Station Server
After=network.target

[Service]
Type=simple
User=weatheruser
Group=weatheruser
WorkingDirectory=/home/weatheruser/public_html
ExecStart=/home/weatheruser/public_html/start-server.sh monitor
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable weatherstation.service
sudo systemctl start weatherstation.service
```

## Step 5: Configure Reverse Proxy (Alternative to Port 80)

### 5.1 Using Apache Virtual Host
```bash
# Create Apache virtual host configuration
sudo cat > /etc/httpd/conf.d/weatherstation.conf << 'EOF'
<VirtualHost *:80>
    ServerName weatherstation.com
    DocumentRoot /home/weatheruser/public_html/public
    
    # Proxy to Node.js app running on port 3000
    ProxyPreserveHost On
    ProxyPass /api/ http://localhost:3000/api/
    ProxyPassReverse /api/ http://localhost:3000/api/
    ProxyPass /tasks/ http://localhost:3000/tasks/
    ProxyPassReverse /tasks/ http://localhost:3000/tasks/
    ProxyPass /health http://localhost:3000/health
    ProxyPassReverse /health http://localhost:3000/health
    
    # Serve static files directly
    <Directory /home/weatheruser/public_html/public>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Restart Apache
sudo systemctl restart httpd
```

### 5.2 Update Environment for Proxy Setup
```bash
# Update .env file for proxy setup
cat >> /home/weatheruser/public_html/.env << 'EOF'
# Use port 3000 for internal app, Apache proxies to port 80
PORT=3000
EOF
```

## Step 6: SSL Certificate Setup (Recommended)

### 6.1 Install Certbot
```bash
# On CentOS/RHEL
sudo yum install -y certbot python3-certbot-apache

# On Ubuntu/Debian
sudo apt install -y certbot python3-certbot-apache
```

### 6.2 Obtain SSL Certificate
```bash
# Get SSL certificate
sudo certbot --apache -d weatherstation.com

# Auto-renewal setup
sudo crontab -e
# Add this line:
# 0 12 * * * /usr/bin/certbot renew --quiet
```

## Step 7: Configure Firewall and Security

### 7.1 Configure Firewall Rules
```bash
# Allow HTTP and HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

### 7.2 Set Proper Permissions
```bash
# Set ownership to cPanel user
sudo chown -R weatheruser:weatheruser /home/weatheruser/public_html

# Set secure permissions
chmod 755 /home/weatheruser/public_html
chmod 644 /home/weatheruser/public_html/.env
chmod 755 /home/weatheruser/public_html/start-server.sh
```

## Step 8: Testing and Verification

### 8.1 Test Application
```bash
# Check service status
sudo systemctl status weatherstation.service

# Check if app is responding
curl http://weatherstation.com/health

# Check logs
tail -f /home/weatheruser/public_html/server.log
```

### 8.2 Test Data Ingestion
```bash
# Test manual data ingestion
curl "http://weatherstation.com/tasks/ingest?token=YOUR_ADMIN_TOKEN"
```

## Step 9: Monitoring and Maintenance

### 9.1 Set Up Log Rotation
```bash
# Create logrotate configuration
sudo cat > /etc/logrotate.d/weatherstation << 'EOF'
/home/weatheruser/public_html/server.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 weatheruser weatheruser
    postrotate
        systemctl reload weatherstation.service
    endscript
}
EOF
```

### 9.2 Set Up Monitoring
```bash
# Create monitoring script
cat > /home/weatheruser/public_html/monitor.sh << 'EOF'
#!/bin/bash

# Simple health check script
HEALTH_URL="http://weatherstation.com/health"
LOG_FILE="/home/weatheruser/public_html/monitor.log"

if curl -f -s "$HEALTH_URL" > /dev/null; then
    echo "$(date): Health check passed" >> "$LOG_FILE"
else
    echo "$(date): Health check failed, restarting service" >> "$LOG_FILE"
    systemctl restart weatherstation.service
fi
EOF

chmod +x /home/weatheruser/public_html/monitor.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/weatheruser/public_html/monitor.sh") | crontab -
```

## Step 10: Troubleshooting

### 10.1 Common Issues

**Port 80 Permission Denied:**
```bash
# Run as root or use authbind
sudo apt install authbind
sudo touch /etc/authbind/byport/80
sudo chown weatheruser:weatheruser /etc/authbind/byport/80
sudo chmod 755 /etc/authbind/byport/80
```

**Service Won't Start:**
```bash
# Check logs
journalctl -u weatherstation.service -f

# Check permissions
ls -la /home/weatheruser/public_html/
```

**API Not Responding:**
```bash
# Check if port is listening
netstat -tlnp | grep :80
# or
ss -tlnp | grep :80
```

### 10.2 Useful Commands

```bash
# Service management
sudo systemctl start weatherstation.service
sudo systemctl stop weatherstation.service
sudo systemctl restart weatherstation.service
sudo systemctl status weatherstation.service

# Log viewing
tail -f /home/weatheruser/public_html/server.log
journalctl -u weatherstation.service -f

# Process monitoring
ps aux | grep node
lsof -i :80
```

## Step 11: Final Configuration

### 11.1 Update DNS Records
Ensure your domain's DNS records point to your server:
```
A Record: weatherstation.com → YOUR_SERVER_IP
```

### 11.2 Test Complete Setup
1. Visit `http://weatherstation.com`
2. Check health endpoint: `http://weatherstation.com/health`
3. Test data ingestion: `http://weatherstation.com/tasks/ingest?token=YOUR_TOKEN`
4. Verify SSL: `https://weatherstation.com`

## Security Considerations

1. **Firewall**: Only allow necessary ports (80, 443, 22)
2. **SSL**: Always use HTTPS in production
3. **Environment Variables**: Keep API keys secure in `.env` file
4. **Updates**: Regularly update Node.js and dependencies
5. **Monitoring**: Set up proper monitoring and alerting
6. **Backups**: Regular backups of application and data

## Support and Maintenance

- Monitor logs regularly
- Keep dependencies updated
- Test after any system updates
- Have a rollback plan ready
- Document any custom configurations

This setup provides a robust, production-ready deployment of your Weather Station app on port 80 in a cPanel environment with proper process management and monitoring.
