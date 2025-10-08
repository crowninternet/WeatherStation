#!/bin/bash
################################################################################
# WeatherStation Datastore Fix Script
# Run this script from the Proxmox HOST to fix corrupted data.json
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

echo "🔧 WeatherStation Datastore Fix Tool"
echo "===================================="
echo ""

# Get container ID
read -p "Enter your WeatherStation container ID: " CONTAINER_ID

if [ -z "$CONTAINER_ID" ]; then
    print_error "Container ID is required"
    exit 1
fi

print_info "Fixing datastore structure in container $CONTAINER_ID..."

# Stop the service first
print_info "Stopping WeatherStation service..."
pct exec $CONTAINER_ID -- systemctl stop weatherstation

# Backup the current data.json
print_info "Backing up current data.json..."
pct exec $CONTAINER_ID -- cp /opt/weatherstation/data/data.json /opt/weatherstation/data/data.json.backup.$(date +%s) 2>/dev/null || true

# Create the proper data structure
print_info "Creating proper datastore structure..."
pct exec $CONTAINER_ID -- bash -c "cat > /opt/weatherstation/data/data.json << 'EOF'
{
  \"meta\": {
    \"version\": 1,
    \"timezone\": \"America/Phoenix\",
    \"lastIngestISO\": null
  },
  \"stations\": {},
  \"readings\": []
}
EOF"

# Set proper permissions
print_info "Setting proper permissions..."
pct exec $CONTAINER_ID -- chown weatherstation:weatherstation /opt/weatherstation/data/data.json
pct exec $CONTAINER_ID -- chmod 644 /opt/weatherstation/data/data.json

# Start the service
print_info "Starting WeatherStation service..."
pct exec $CONTAINER_ID -- systemctl start weatherstation

# Wait for service to start
sleep 5

# Check service status
if pct exec $CONTAINER_ID -- systemctl is-active weatherstation > /dev/null 2>&1; then
    print_success "Service is running"
else
    print_error "Service failed to start"
    pct exec $CONTAINER_ID -- journalctl -u weatherstation -n 10 --no-pager
    exit 1
fi

# Get container IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

# Trigger data ingestion
print_info "Triggering data ingestion..."
curl -s "http://$CONTAINER_IP:3333/tasks/ingest?token=W8*q#G\$4pKR058oL" > /dev/null

# Wait for ingestion to complete
sleep 10

# Check if stations are now available
print_info "Checking stations..."
STATIONS_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/api/stations")

if [ "$STATIONS_RESPONSE" != "[]" ] && [ ! -z "$STATIONS_RESPONSE" ] && [ "$STATIONS_RESPONSE" != '{"error":"Failed to fetch stations"}' ]; then
    print_success "Stations found: $STATIONS_RESPONSE"
    echo ""
    print_success "🎉 Fix successful! Your WeatherStation is now working properly."
    print_info "Open http://$CONTAINER_IP:3333 in your browser to view the dashboard."
else
    print_warning "Stations still not found. Checking logs..."
    pct exec $CONTAINER_ID -- journalctl -u weatherstation -n 15 --no-pager
fi

echo ""
print_info "Fix complete!"
