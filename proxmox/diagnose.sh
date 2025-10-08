#!/bin/bash
################################################################################
# WeatherStation Diagnostic Script for Proxmox
# Run this script from the Proxmox HOST to diagnose issues
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

echo "🔍 WeatherStation Diagnostic Tool"
echo "================================="
echo ""

# Get container ID
read -p "Enter your WeatherStation container ID: " CONTAINER_ID

if [ -z "$CONTAINER_ID" ]; then
    print_error "Container ID is required"
    exit 1
fi

echo ""
print_info "Checking container status..."

# Check if container exists and is running
if ! pct list | grep -q "$CONTAINER_ID"; then
    print_error "Container $CONTAINER_ID not found"
    exit 1
fi

if ! pct list | grep "$CONTAINER_ID" | grep -q "running"; then
    print_error "Container $CONTAINER_ID is not running"
    exit 1
fi

print_success "Container $CONTAINER_ID is running"

# Get container IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
print_info "Container IP: $CONTAINER_IP"

echo ""
print_info "Checking WeatherStation service..."

# Check service status
if pct exec $CONTAINER_ID -- systemctl is-active weatherstation > /dev/null 2>&1; then
    print_success "WeatherStation service is running"
else
    print_error "WeatherStation service is not running"
    print_info "Service status:"
    pct exec $CONTAINER_ID -- systemctl status weatherstation --no-pager
    exit 1
fi

echo ""
print_info "Checking application health..."

# Check health endpoint
if curl -s "http://$CONTAINER_IP:3333/health" > /dev/null; then
    print_success "Application is responding"
    HEALTH_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/health")
    print_info "Health response: $HEALTH_RESPONSE"
else
    print_error "Application is not responding on port 3333"
    exit 1
fi

echo ""
print_info "Checking API configuration..."

# Check if .env file exists and has content
if pct exec $CONTAINER_ID -- [ -f /opt/weatherstation/.env ]; then
    print_success ".env file exists"
    
    # Check if API keys are configured
    if pct exec $CONTAINER_ID -- grep -q "AMBIENT_API_KEY=" /opt/weatherstation/.env; then
        API_KEY=$(pct exec $CONTAINER_ID -- grep "AMBIENT_API_KEY=" /opt/weatherstation/.env | cut -d= -f2)
        if [ "$API_KEY" != "your_api_key_here" ] && [ ! -z "$API_KEY" ]; then
            print_success "API Key is configured"
        else
            print_error "API Key is not properly configured"
        fi
    else
        print_error "API Key not found in .env file"
    fi
    
    if pct exec $CONTAINER_ID -- grep -q "AMBIENT_APP_KEY=" /opt/weatherstation/.env; then
        APP_KEY=$(pct exec $CONTAINER_ID -- grep "AMBIENT_APP_KEY=" /opt/weatherstation/.env | cut -d= -f2)
        if [ "$APP_KEY" != "your_application_key_here" ] && [ ! -z "$APP_KEY" ]; then
            print_success "Application Key is configured"
        else
            print_error "Application Key is not properly configured"
        fi
    else
        print_error "Application Key not found in .env file"
    fi
else
    print_error ".env file not found"
fi

echo ""
print_info "Checking stations API..."

# Check stations endpoint
STATIONS_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/api/stations")
if [ $? -eq 0 ]; then
    if [ "$STATIONS_RESPONSE" = "[]" ]; then
        print_warning "No stations found - this is the problem!"
        print_info "Stations response: $STATIONS_RESPONSE"
    else
        print_success "Stations found: $STATIONS_RESPONSE"
    fi
else
    print_error "Failed to get stations data"
fi

echo ""
print_info "Checking data directory..."

# Check data directory and file
if pct exec $CONTAINER_ID -- [ -d /opt/weatherstation/data ]; then
    print_success "Data directory exists"
    
    if pct exec $CONTAINER_ID -- [ -f /opt/weatherstation/data/data.json ]; then
        print_success "data.json file exists"
        DATA_SIZE=$(pct exec $CONTAINER_ID -- wc -c < /opt/weatherstation/data/data.json)
        print_info "Data file size: $DATA_SIZE bytes"
        
        if [ "$DATA_SIZE" -gt 10 ]; then
            print_success "Data file has content"
        else
            print_warning "Data file appears empty or minimal"
        fi
    else
        print_error "data.json file not found"
    fi
else
    print_error "Data directory not found"
fi

echo ""
print_info "Testing API connectivity..."

# Test external API connectivity
if pct exec $CONTAINER_ID -- ping -c 1 api.ambientweather.net > /dev/null 2>&1; then
    print_success "Can reach AmbientWeather API"
else
    print_error "Cannot reach AmbientWeather API"
fi

echo ""
print_info "Recent service logs..."

# Show recent logs
pct exec $CONTAINER_ID -- journalctl -u weatherstation -n 20 --no-pager

echo ""
print_info "Attempting manual data ingestion..."

# Try manual ingestion
ADMIN_TOKEN=$(pct exec $CONTAINER_ID -- grep "ADMIN_TOKEN=" /opt/weatherstation/.env | cut -d= -f2)
if [ ! -z "$ADMIN_TOKEN" ]; then
    print_info "Triggering manual data ingestion..."
    INGEST_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/tasks/ingest?token=$ADMIN_TOKEN")
    if [ $? -eq 0 ]; then
        print_success "Manual ingestion completed"
        print_info "Ingest response: $INGEST_RESPONSE"
        
        # Wait a moment and check stations again
        sleep 3
        STATIONS_RESPONSE=$(curl -s "http://$CONTAINER_IP:3333/api/stations")
        if [ "$STATIONS_RESPONSE" != "[]" ]; then
            print_success "Stations now available: $STATIONS_RESPONSE"
        else
            print_warning "Still no stations after manual ingestion"
        fi
    else
        print_error "Manual ingestion failed"
    fi
else
    print_error "Admin token not found"
fi

echo ""
print_info "Diagnostic complete!"
echo ""
print_info "If stations are still not showing:"
echo "1. Check your AmbientWeather API credentials are correct"
echo "2. Verify your weather stations are online and sending data"
echo "3. Check the AmbientWeather dashboard at https://ambientweather.net/"
echo "4. Try restarting the service: pct exec $CONTAINER_ID -- systemctl restart weatherstation"
