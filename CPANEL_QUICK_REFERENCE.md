# Weather Station App - cPanel Deployment Quick Reference

## Prerequisites
- WHM access to create cPanel accounts
- Node.js installed on server
- SSH access to server
- Domain name pointing to server

## Quick Setup (Automated)

### 1. Create cPanel Account via WHM
- Domain: `weatherstation.yourdomain.com`
- Username: `weatheruser`
- Package: Select appropriate package

### 2. Run Deployment Script
```bash
# Download and run the deployment script
sudo ./deploy-cpanel.sh weatheruser weatherstation.yourdomain.com 80
```

### 3. Upload Application Files
```bash
# Upload files to cPanel account
scp -r . weatheruser@your-server:/home/weatheruser/public_html/
```

### 4. Install Dependencies
```bash
# SSH into server
ssh weatheruser@your-server

# Install dependencies
cd /home/weatheruser/public_html
npm install --production
```

### 5. Configure Environment
```bash
# Edit .env file with your API keys
nano .env
```

### 6. Start Service
```bash
# Start the service
sudo systemctl start weatherstation.service
sudo systemctl enable weatherstation.service
```

## Manual Setup (Step-by-Step)

### 1. Server Preparation
```bash
# Install Node.js
sudo yum install -y nodejs npm  # CentOS/RHEL
sudo apt install -y nodejs npm  # Ubuntu/Debian

# Configure firewall
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

### 2. Deploy Application
```bash
# Navigate to cPanel account directory
cd /home/weatheruser/public_html

# Upload application files
# Install dependencies
npm install --production
```

### 3. Create Environment File
```bash
cat > .env << 'EOF'
AMBIENT_API_KEY=your_api_key_here
AMBIENT_APP_KEY=your_application_key_here
PORT=80
NODE_ENV=production
ADMIN_TOKEN=your_secure_token_here
INGEST_LIMIT=200
TIMEZONE=America/New_York
EOF
```

### 4. Create Process Management Script
```bash
# Copy the start-server.sh script from the main deployment guide
# Make it executable
chmod +x start-server.sh
```

### 5. Create Systemd Service
```bash
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
```

### 6. Configure Apache Virtual Host
```bash
sudo cat > /etc/httpd/conf.d/weatherstation.conf << 'EOF'
<VirtualHost *:80>
    ServerName weatherstation.yourdomain.com
    DocumentRoot /home/weatheruser/public_html/public
    
    ProxyPreserveHost On
    ProxyPass /api/ http://localhost:80/api/
    ProxyPassReverse /api/ http://localhost:80/api/
    ProxyPass /tasks/ http://localhost:80/tasks/
    ProxyPassReverse /tasks/ http://localhost:80/tasks/
    ProxyPass /health http://localhost:80/health
    ProxyPassReverse /health http://localhost:80/health
    
    <Directory /home/weatheruser/public_html/public>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
```

### 7. Start Services
```bash
# Reload systemd and start service
sudo systemctl daemon-reload
sudo systemctl enable weatherstation.service
sudo systemctl start weatherstation.service

# Restart Apache
sudo systemctl restart httpd
```

## Service Management Commands

```bash
# Service control
sudo systemctl start weatherstation.service
sudo systemctl stop weatherstation.service
sudo systemctl restart weatherstation.service
sudo systemctl status weatherstation.service

# View logs
sudo journalctl -u weatherstation.service -f
tail -f /home/weatheruser/public_html/server.log

# Check if running
ps aux | grep node
lsof -i :80
```

## Testing

```bash
# Health check
curl http://weatherstation.yourdomain.com/health

# Test data ingestion
curl "http://weatherstation.yourdomain.com/tasks/ingest?token=YOUR_ADMIN_TOKEN"

# Check service status
sudo systemctl status weatherstation.service
```

## SSL Setup (Recommended)

```bash
# Install Certbot
sudo yum install -y certbot python3-certbot-apache  # CentOS/RHEL
sudo apt install -y certbot python3-certbot-apache  # Ubuntu/Debian

# Get SSL certificate
sudo certbot --apache -d weatherstation.yourdomain.com

# Auto-renewal
sudo crontab -e
# Add: 0 12 * * * /usr/bin/certbot renew --quiet
```

## Troubleshooting

### Common Issues

**Port 80 Permission Denied:**
```bash
# Use authbind for non-root users
sudo apt install authbind
sudo touch /etc/authbind/byport/80
sudo chown weatheruser:weatheruser /etc/authbind/byport/80
sudo chmod 755 /etc/authbind/byport/80
```

**Service Won't Start:**
```bash
# Check logs
sudo journalctl -u weatherstation.service -f
tail -f /home/weatheruser/public_html/server.log

# Check permissions
ls -la /home/weatheruser/public_html/
```

**API Not Responding:**
```bash
# Check if port is listening
netstat -tlnp | grep :80
ss -tlnp | grep :80

# Test local connection
curl http://localhost:80/health
```

### Useful Commands

```bash
# Check system resources
htop
df -h
free -h

# Check network connections
netstat -tlnp
ss -tlnp

# Check processes
ps aux | grep node
ps aux | grep weatherstation

# Check logs
tail -f /home/weatheruser/public_html/server.log
sudo journalctl -u weatherstation.service --since "1 hour ago"
```

## Security Checklist

- [ ] Firewall configured (ports 80, 443, 22 only)
- [ ] SSL certificate installed
- [ ] Environment variables secured
- [ ] Regular updates scheduled
- [ ] Monitoring configured
- [ ] Backups scheduled
- [ ] Log rotation configured

## URLs

- **Main App**: http://weatherstation.yourdomain.com
- **Health Check**: http://weatherstation.yourdomain.com/health
- **API**: http://weatherstation.yourdomain.com/api/stations
- **Data Ingestion**: http://weatherstation.yourdomain.com/tasks/ingest?token=YOUR_TOKEN

## File Locations

- **App Directory**: `/home/weatheruser/public_html/`
- **Service File**: `/etc/systemd/system/weatherstation.service`
- **Apache Config**: `/etc/httpd/conf.d/weatherstation.conf`
- **Logs**: `/home/weatheruser/public_html/server.log`
- **Environment**: `/home/weatheruser/public_html/.env`
