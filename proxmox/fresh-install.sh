#!/bin/bash
################################################################################
# WeatherStation - Fresh Installation Script for Proxmox
# Run this script from the Proxmox HOST (not in a container)
#
# This script will:
# 1. Create a new LXC container
# 2. Install Node.js and dependencies
# 3. Install WeatherStation application
# 4. Configure systemd service
# 5. Start monitoring automatically
#
# Usage: ./fresh-install.sh
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Check if running on Proxmox host
if ! command -v pct &> /dev/null; then
    print_error "This script must be run from a Proxmox host"
    print_info "Make sure you're running this from the Proxmox host, not inside a container"
    exit 1
fi

print_header "WeatherStation - Fresh Install"
echo ""

# Configuration
CONTAINER_NAME="weatherstation"
INSTALL_DIR="/opt/weatherstation"
SERVICE_NAME="weatherstation"
APP_USER="weatherstation"

# Ask for container configuration
read -p "Enter container ID (e.g., 100): " CONTAINER_ID
if [ -z "$CONTAINER_ID" ]; then
    print_error "Container ID cannot be empty"
    exit 1
fi

read -p "Enter hostname [weatherstation]: " HOSTNAME
HOSTNAME=${HOSTNAME:-weatherstation}

read -p "Enter disk size in GB [4]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-4}

read -p "Enter RAM in MB [512]: " RAM
RAM=${RAM:-512}

read -p "Enter storage pool [local-lxc]: " STORAGE
STORAGE=${STORAGE:-local-lxc}

echo ""
print_warning "This will create container $CONTAINER_ID with:"
echo "  Hostname: $HOSTNAME"
echo "  Disk: ${DISK_SIZE}GB"
echo "  RAM: ${RAM}MB"
echo "  Storage: $STORAGE"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installation cancelled"
    exit 0
fi

echo ""
print_header "Step 1: Creating LXC Container"
echo ""

# Find latest Debian 12 template
print_info "Finding Debian 12 template..."
DEBIAN_TEMPLATE=$(pveam list local | grep "debian-12-standard" | awk '{print $1}' | head -1)
if [ -z "$DEBIAN_TEMPLATE" ]; then
    print_error "No Debian 12 template found in local storage"
    print_info "Download one with: pveam download local debian-12-standard"
    exit 1
fi

print_info "Using template: $DEBIAN_TEMPLATE"

# Create container
print_info "Creating Debian 12 container..."
pct create $CONTAINER_ID \
    $DEBIAN_TEMPLATE \
    --hostname $HOSTNAME \
    --memory $RAM \
    --rootfs $STORAGE:$DISK_SIZE \
    --cores 1 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --features nesting=1 \
    --unprivileged 1 \
    --onboot 1

print_success "Container created with ID: $CONTAINER_ID"

echo ""
print_info "Starting container..."
pct start $CONTAINER_ID
sleep 5
print_success "Container started"

echo ""
print_header "Step 2: Installing Base System"
echo ""

print_info "Updating package list..."
pct exec $CONTAINER_ID -- apt-get update -qq

print_info "Installing base packages..."
pct exec $CONTAINER_ID -- apt-get install -y curl wget ca-certificates gnupg

print_success "Base system updated"

echo ""
print_header "Step 3: Installing Node.js"
echo ""

print_info "Adding NodeSource repository..."
pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"

print_info "Installing Node.js..."
pct exec $CONTAINER_ID -- apt-get install -y nodejs

NODE_VERSION=$(pct exec $CONTAINER_ID -- node --version)
print_success "Node.js installed: $NODE_VERSION"

echo ""
print_header "Step 4: Creating Application User"
echo ""

print_info "Creating $APP_USER user..."
pct exec $CONTAINER_ID -- useradd -r -m -s /bin/bash $APP_USER
print_success "User created"

echo ""
print_header "Step 5: Installing WeatherStation"
echo ""

print_info "Creating application directory..."
pct exec $CONTAINER_ID -- mkdir -p $INSTALL_DIR
pct exec $CONTAINER_ID -- mkdir -p $INSTALL_DIR/data
pct exec $CONTAINER_ID -- mkdir -p $INSTALL_DIR/app/routes
pct exec $CONTAINER_ID -- mkdir -p $INSTALL_DIR/app/utils
pct exec $CONTAINER_ID -- mkdir -p $INSTALL_DIR/public/assets

print_info "Downloading application files..."

# Download main server file
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/server.js -o server.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download server.js"
    exit 1
fi

# Download package.json
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/package.json -o package.json"
if [ $? -ne 0 ]; then
    print_error "Failed to download package.json"
    exit 1
fi

# Download app files
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/datastore.js -o app/datastore.js"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/ambientClient.js -o app/ambientClient.js"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/mutex.js -o app/mutex.js"

# Download route files
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/routes/api.js -o app/routes/api.js"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/routes/tasks.js -o app/routes/tasks.js"

# Download utility files
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/utils/csv.js -o app/utils/csv.js"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/utils/dates.js -o app/utils/dates.js"

# Download public files
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/index.html -o public/index.html"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/history.html -o public/history.html"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/assets/app.css -o public/assets/app.css"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/assets/app.js -o public/assets/app.js"

print_success "Files downloaded"

echo ""
print_info "Installing Node.js dependencies..."
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && npm install --production"

print_success "Dependencies installed"

echo ""
print_info "Setting up data directory..."
pct exec $CONTAINER_ID -- bash -c "echo '{}' > $INSTALL_DIR/data/data.json"

print_info "Setting permissions..."
pct exec $CONTAINER_ID -- chown -R $APP_USER:$APP_USER $INSTALL_DIR
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/data
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/app
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/app/routes
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/app/utils
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/public
pct exec $CONTAINER_ID -- chmod 755 $INSTALL_DIR/public/assets

# Set permissions for files that exist
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && find . -name '*.js' -exec chmod 644 {} \;"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && find . -name '*.html' -exec chmod 644 {} \;"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && find . -name '*.css' -exec chmod 644 {} \;"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && find . -name '*.json' -exec chmod 644 {} \;"

print_success "Permissions set"

echo ""
print_header "Step 6: Installing systemd Service"
echo ""

print_info "Creating service file..."
pct exec $CONTAINER_ID -- bash -c "cat > /etc/systemd/system/$SERVICE_NAME.service << 'EOF'
[Unit]
Description=WeatherStation - AmbientWeather Viewer & Archiver
Documentation=https://github.com/crowninternet/WeatherStation
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Resource limits
MemoryMax=512M
CPUQuota=50%
LimitNOFILE=4096
LimitNPROC=2048

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true
RestrictNamespaces=true

# Environment
Environment=NODE_ENV=production
Environment=PORT=3333

[Install]
WantedBy=multi-user.target
EOF"

print_info "Reloading systemd..."
pct exec $CONTAINER_ID -- systemctl daemon-reload

print_info "Enabling service..."
pct exec $CONTAINER_ID -- systemctl enable $SERVICE_NAME

print_success "Service installed"

echo ""
print_header "Step 7: Starting Service"
echo ""

print_info "Starting $SERVICE_NAME..."
pct exec $CONTAINER_ID -- systemctl start $SERVICE_NAME
sleep 3

if pct exec $CONTAINER_ID -- systemctl is-active $SERVICE_NAME > /dev/null 2>&1; then
    print_success "Service is running!"
else
    print_error "Service failed to start"
    print_info "Checking logs..."
    pct exec $CONTAINER_ID -- journalctl -u $SERVICE_NAME -n 20 --no-pager
    exit 1
fi

echo ""
print_header "Step 8: Verifying Installation"
echo ""

print_info "Waiting for service to initialize..."
sleep 5

print_info "Checking health endpoint..."
if pct exec $CONTAINER_ID -- curl -s http://localhost:3333/health > /dev/null 2>&1; then
    print_success "WeatherStation is responding!"
else
    print_warning "Service not responding yet (may still be starting)"
fi

echo ""
# Get container IP
print_info "Getting container IP address..."
CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')
print_success "Container IP: $CONTAINER_IP"

echo ""
print_header "Installation Complete!"
echo ""
print_success "WeatherStation is now running!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🌤️  Access Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Container ID: $CONTAINER_ID"
echo "  Hostname: $HOSTNAME"
echo "  IP Address: $CONTAINER_IP"
echo "  Web Interface: http://$CONTAINER_IP:3333"
echo "  Health Check: http://$CONTAINER_IP:3333/health"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 📝 Management Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Start:   pct exec $CONTAINER_ID -- systemctl start $SERVICE_NAME"
echo "  Stop:    pct exec $CONTAINER_ID -- systemctl stop $SERVICE_NAME"
echo "  Restart: pct exec $CONTAINER_ID -- systemctl restart $SERVICE_NAME"
echo "  Status:  pct exec $CONTAINER_ID -- systemctl status $SERVICE_NAME"
echo "  Logs:    pct exec $CONTAINER_ID -- journalctl -u $SERVICE_NAME -f"
echo "  Enter:   pct enter $CONTAINER_ID"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ⚙️  Configuration Required"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " 1. Create .env file with your AmbientWeather API credentials:"
echo "    pct exec $CONTAINER_ID -- bash -c \"cat > $INSTALL_DIR/.env << 'ENVEOF'"
echo "    AMBIENT_API_KEY=your_api_key_here"
echo "    AMBIENT_APP_KEY=your_application_key_here"
echo "    ADMIN_TOKEN=your_secure_token_here"
echo "    PORT=3333"
echo "    TIMEZONE=America/New_York"
echo "    ENVEOF\""
echo ""
echo " 2. Restart the service after configuration:"
echo "    pct exec $CONTAINER_ID -- systemctl restart $SERVICE_NAME"
echo ""
echo " 3. Trigger initial data ingestion:"
echo "    curl \"http://$CONTAINER_IP:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✨ Features Enabled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " ✅ Real-time weather dashboard"
echo " ✅ Historical data charts"
echo " ✅ Automatic data ingestion"
echo " ✅ Responsive web interface"
echo " ✅ Auto-restart on failure"
echo " ✅ Survives container reboots"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🚀 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " 1. Open http://$CONTAINER_IP:3333 in your browser"
echo " 2. Configure your AmbientWeather API credentials"
echo " 3. Trigger initial data ingestion"
echo " 4. View your weather dashboard!"
echo ""
print_info "WeatherStation will run 24/7 in the background!"
echo ""
