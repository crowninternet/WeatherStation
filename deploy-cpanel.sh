#!/bin/bash

# Weather Station App - cPanel Deployment Script
# This script automates the deployment process for cPanel/WHM environments

set -e

# Configuration variables
CPANEL_USER="${1:-weatheruser}"
CPANEL_DOMAIN="${2:-weatherstation.com}"
APP_DIR="/home/$CPANEL_USER/public_html"
NODE_PORT="${3:-80}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (use sudo)"
fi

# Check if cPanel user exists
if ! id "$CPANEL_USER" &>/dev/null; then
    error "cPanel user '$CPANEL_USER' does not exist. Please create the account first."
fi

log "Starting Weather Station deployment for user: $CPANEL_USER"
log "Domain: $CPANEL_DOMAIN"
log "App directory: $APP_DIR"
log "Port: $NODE_PORT"

# Step 1: Install Node.js if not present
log "Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    log "Installing Node.js..."
    
    # Detect OS and install Node.js
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        yum install -y nodejs
    elif [ -f /etc/debian_version ]; then
        # Ubuntu/Debian
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    else
        error "Unsupported operating system"
    fi
else
    log "Node.js is already installed: $(node --version)"
fi

# Step 2: Set up application directory
log "Setting up application directory..."
mkdir -p "$APP_DIR"
cd "$APP_DIR"

# Step 3: Create environment file
log "Creating environment configuration..."
cat > .env << EOF
# AmbientWeather API Configuration
AMBIENT_API_KEY=your_api_key_here
AMBIENT_APP_KEY=your_application_key_here

# Server configuration
PORT=$NODE_PORT
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

# Step 4: Create startup script
log "Creating process management script..."
cat > start-server.sh << 'EOF'
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
    echo "$(date): Starting Weather Station Server..." >> "$LOG_FILE"
    cd "$SCRIPT_DIR"
    
    # Kill any existing processes on the configured port
    PORT=$(grep "^PORT=" .env | cut -d'=' -f2)
    lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
    
    # Start the server
    nohup node "$SERVER_FILE" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    echo "$(date): Server started with PID $pid on port $PORT" >> "$LOG_FILE"
    echo "Server started with PID $pid on port $PORT"
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

chmod +x start-server.sh

# Step 5: Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/weatherstation.service << EOF
[Unit]
Description=Weather Station Server
After=network.target

[Service]
Type=simple
User=$CPANEL_USER
Group=$CPANEL_USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/start-server.sh monitor
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Step 6: Configure Apache virtual host
log "Creating Apache virtual host configuration..."
cat > /etc/httpd/conf.d/weatherstation.conf << EOF
<VirtualHost *:80>
    ServerName $CPANEL_DOMAIN
    DocumentRoot $APP_DIR/public
    
    # Proxy to Node.js app
    ProxyPreserveHost On
    ProxyPass /api/ http://localhost:$NODE_PORT/api/
    ProxyPassReverse /api/ http://localhost:$NODE_PORT/api/
    ProxyPass /tasks/ http://localhost:$NODE_PORT/tasks/
    ProxyPassReverse /tasks/ http://localhost:$NODE_PORT/tasks/
    ProxyPass /health http://localhost:$NODE_PORT/health
    ProxyPassReverse /health http://localhost:$NODE_PORT/health
    
    # Serve static files directly
    <Directory $APP_DIR/public>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Step 7: Set permissions
log "Setting proper permissions..."
chown -R "$CPANEL_USER:$CPANEL_USER" "$APP_DIR"
chmod 755 "$APP_DIR"
chmod 644 "$APP_DIR/.env"
chmod 755 "$APP_DIR/start-server.sh"

# Step 8: Configure firewall
log "Configuring firewall..."
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
fi

# Step 9: Enable and start services
log "Enabling and starting services..."
systemctl daemon-reload
systemctl enable weatherstation.service

# Restart Apache
if systemctl is-active --quiet httpd; then
    systemctl restart httpd
elif systemctl is-active --quiet apache2; then
    systemctl restart apache2
fi

# Step 10: Create monitoring script
log "Creating monitoring script..."
cat > "$APP_DIR/monitor.sh" << 'EOF'
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

chmod +x "$APP_DIR/monitor.sh"

# Add monitoring to crontab
(crontab -u "$CPANEL_USER" -l 2>/dev/null; echo "*/5 * * * * $APP_DIR/monitor.sh") | crontab -u "$CPANEL_USER" -

# Step 11: Create log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/weatherstation << EOF
$APP_DIR/server.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $CPANEL_USER $CPANEL_USER
    postrotate
        systemctl reload weatherstation.service
    endscript
}
EOF

# Final instructions
log "Deployment completed successfully!"
echo ""
echo "Next steps:"
echo "1. Upload your application files to: $APP_DIR"
echo "2. Run 'npm install' in the application directory"
echo "3. Update the .env file with your actual API keys"
echo "4. Start the service: systemctl start weatherstation.service"
echo "5. Check status: systemctl status weatherstation.service"
echo "6. View logs: tail -f $APP_DIR/server.log"
echo ""
echo "Service management commands:"
echo "  Start:   systemctl start weatherstation.service"
echo "  Stop:    systemctl stop weatherstation.service"
echo "  Restart: systemctl restart weatherstation.service"
echo "  Status:  systemctl status weatherstation.service"
echo ""
echo "Application will be available at: http://$CPANEL_DOMAIN"
echo "Health check: http://$CPANEL_DOMAIN/health"
echo ""
warning "Remember to:"
echo "  - Update .env file with real API keys"
echo "  - Upload your application files"
echo "  - Run 'npm install' to install dependencies"
echo "  - Configure SSL certificate for production use"
