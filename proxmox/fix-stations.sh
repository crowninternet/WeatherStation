#!/bin/bash
################################################################################
# WeatherStation Quick Fix Script for Proxmox
# Run this script from the Proxmox HOST to fix station data issues
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

echo "🔧 WeatherStation Quick Fix Tool"
echo "================================"
echo ""

# Get container ID
read -p "Enter your WeatherStation container ID: " CONTAINER_ID

if [ -z "$CONTAINER_ID" ]; then
    print_error "Container ID is required"
    exit 1
fi

# Get container IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
print_info "Container IP: $CONTAINER_IP"

echo ""
print_info "Step 1: Restarting WeatherStation service..."
pct exec $CONTAINER_ID -- systemctl restart weatherstation
sleep 5
print_success "Service restarted"

echo ""
print_info "Step 2: Triggering data ingestion..."
ADMIN_TOKEN=$(pct exec $CONTAINER_ID -- grep "ADMIN_TOKEN=" /opt/weatherstation/.env | cut -d= -f2)
if [ ! -z "$ADMIN_TOKEN" ]; then
    curl -s "http://$CONTAINER_IP:3333/tasks/ingest?token=$ADMIN_TOKEN"
    print_success "Data ingestion triggered"
else
    print_error "Admin token not found"
    exit 1
fi

echo ""
print_info "Step 3: Waiting for data to load..."
sleep 10

echo ""
print_info "Step 4: Checking stations..."
STATIONS_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/api/stations")
if [ "$STATIONS_RESPONSE" != "[]" ] && [ ! -z "$STATIONS_RESPONSE" ]; then
    print_success "Stations found: $STATIONS_RESPONSE"
    echo ""
    print_info "✅ Fix successful! Your weather stations should now be visible."
    print_info "Open http://$CONTAINER_IP:3333 in your browser to view the dashboard."
else
    print_warning "Still no stations found. This might indicate:"
    echo ""
    echo "1. Your AmbientWeather API credentials may be incorrect"
    echo "2. Your weather stations may not be online"
    echo "3. There may be a network connectivity issue"
    echo ""
    print_info "Run the diagnostic script for more details:"
    echo "./proxmox/diagnose.sh"
fi

echo ""
print_info "Step 5: Checking service logs..."
print_info "Recent logs:"
pct exec $CONTAINER_ID -- journalctl -u weatherstation -n 10 --no-pager
