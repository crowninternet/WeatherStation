#!/bin/bash
################################################################################
# WeatherStation - Fresh Installation Script for Proxmox v5
# Run this script from the Proxmox HOST (not in a container)
#
# This script will:
# 1. Create a new LXC container
# 2. Install Node.js and dependencies
# 3. Install WeatherStation application
# 4. Configure systemd service
# 5. Start monitoring automatically
#
# Usage: ./fresh-install-v5.sh
# Or: bash -c "$(curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install-v5.sh)"
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_header() { echo -e "${PURPLE}================================${NC}"; echo -e "${PURPLE}$1${NC}"; echo -e "${PURPLE}================================${NC}"; }

# Check if running on Proxmox host
if ! command -v pct &> /dev/null; then
    print_error "This script must be run from a Proxmox host"
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
echo
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
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/server.js -o server.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download server.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/package.json -o package.json"
if [ $? -ne 0 ]; then
    print_error "Failed to download package.json"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/datastore.js -o app/datastore.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download datastore.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/ambientClient.js -o app/ambientClient.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download ambientClient.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/mutex.js -o app/mutex.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download mutex.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/routes/api.js -o app/routes/api.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download api.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/routes/tasks.js -o app/routes/tasks.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download tasks.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/utils/csv.js -o app/utils/csv.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download csv.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/app/utils/dates.js -o app/utils/dates.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download dates.js"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/index.html -o public/index.html"
if [ $? -ne 0 ]; then
    print_error "Failed to download index.html"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/history.html -o public/history.html"
if [ $? -ne 0 ]; then
    print_error "Failed to download history.html"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/assets/app.css -o public/assets/app.css"
if [ $? -ne 0 ]; then
    print_error "Failed to download app.css"
    exit 1
fi

pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/public/assets/app.js -o public/assets/app.js"
if [ $? -ne 0 ]; then
    print_error "Failed to download app.js"
    exit 1
fi

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
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f server.js ] && chmod 644 server.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f package.json ] && chmod 644 package.json || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/datastore.js ] && chmod 644 app/datastore.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/ambientClient.js ] && chmod 644 app/ambientClient.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/mutex.js ] && chmod 644 app/mutex.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/routes/api.js ] && chmod 644 app/routes/api.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/routes/tasks.js ] && chmod 644 app/routes/tasks.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/utils/csv.js ] && chmod 644 app/utils/csv.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f app/utils/dates.js ] && chmod 644 app/utils/dates.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f public/index.html ] && chmod 644 public/index.html || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f public/history.html ] && chmod 644 public/history.html || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f public/assets/app.css ] && chmod 644 public/assets/app.css || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR && [ -f public/assets/app.js ] && chmod 644 public/assets/app.js || true"
pct exec $CONTAINER_ID -- bash -c "cd $INSTALL_DIR/data && [ -f data.json ] && chmod 644 data.json || true"

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

print_info "Checking API health..."
if pct exec $CONTAINER_ID -- curl -s http://localhost:3333/health > /dev/null 2>&1; then
    print_success "API is responding"
else
    print_warning "API not responding yet (may still be starting)"
fi

print_info "Checking weather data ingestion..."
WEATHER_STATUS=$(pct exec $CONTAINER_ID -- curl -s http://localhost:3333/api/stations 2>/dev/null)
if echo "$WEATHER_STATUS" | grep -q '"stations"'; then
    print_success "Weather data API is active!"
    echo "$WEATHER_STATUS" | python3 -m json.tool 2>/dev/null || echo "$WEATHER_STATUS"
else
    print_warning "Weather API not responding yet (may need configuration)"
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
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 📝 Management Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Start: pct exec $CONTAINER_ID -- systemctl start $SERVICE_NAME"
echo "  Stop: pct exec $CONTAINER_ID -- systemctl stop $SERVICE_NAME"
echo "  Restart: pct exec $CONTAINER_ID -- systemctl restart $SERVICE_NAME"
echo "  Status: pct exec $CONTAINER_ID -- systemctl status $SERVICE_NAME"
echo "  Logs: pct exec $CONTAINER_ID -- journalctl -u $SERVICE_NAME -f"
echo "  Enter Container: pct enter $CONTAINER_ID"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✨ Features Enabled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " ✅ Real-time weather dashboard (24/7)"
echo " ✅ Historical data charts"
echo " ✅ Automatic data ingestion from AmbientWeather API"
echo " ✅ Responsive web interface"
echo " ✅ Auto-restart on failure"
echo " ✅ Survives container reboots"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🚀 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " 1. Open http://$CONTAINER_IP:3333 in your browser"
echo " 2. Get API credentials from https://ambientweather.net/account/api-keys"
echo " 3. Enter container: pct enter $CONTAINER_ID"
echo " 4. Edit config: nano /opt/weatherstation/.env"
echo " 5. Add credentials: AMBIENT_API_KEY=xxx, AMBIENT_APP_KEY=xxx"
echo " 6. Restart service: systemctl restart weatherstation"
echo " 7. Trigger ingestion: curl 'http://$CONTAINER_IP:3333/tasks/ingest?token=TOKEN'"
echo " 8. View your weather dashboard!"
echo ""
echo "⚠️  If you see 'Failed to load station data', you need to configure API credentials!"
echo "📖 See proxmox/TROUBLESHOOTING.md for detailed help"
echo ""
print_info "Weather monitoring will run 24/7 in the background!"
echo ""