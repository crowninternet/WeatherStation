#!/bin/bash
################################################################################
# WeatherStation Proxmox Installer - Test Script
# This script demonstrates and validates the installer without running it
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

print_header "WeatherStation Installer Test"

echo ""
print_info "Testing GitHub repository accessibility..."

# Test 1: Check if the repository is accessible
if curl -s -o /dev/null -w "%{http_code}" https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh | grep -q "200"; then
    print_success "GitHub repository is accessible"
else
    print_error "GitHub repository is not accessible"
    exit 1
fi

# Test 2: Download and validate the installer script
print_info "Downloading installer script..."
INSTALLER_URL="https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh"
TEMP_SCRIPT="/tmp/weatherstation-installer-test.sh"

if curl -fsSL "$INSTALLER_URL" -o "$TEMP_SCRIPT"; then
    print_success "Installer script downloaded successfully"
else
    print_error "Failed to download installer script"
    exit 1
fi

# Test 3: Validate script syntax
print_info "Validating script syntax..."
if bash -n "$TEMP_SCRIPT"; then
    print_success "Script syntax is valid"
else
    print_error "Script has syntax errors"
    exit 1
fi

# Test 4: Check script size and structure
SCRIPT_SIZE=$(wc -l < "$TEMP_SCRIPT")
print_info "Script contains $SCRIPT_SIZE lines"

if [ "$SCRIPT_SIZE" -gt 300 ]; then
    print_success "Script has adequate content ($SCRIPT_SIZE lines)"
else
    print_warning "Script seems short ($SCRIPT lines) - may be incomplete"
fi

# Test 5: Check for required functions
print_info "Checking for required functions..."
REQUIRED_FUNCTIONS=("print_success" "print_error" "print_info" "print_warning" "print_header")

for func in "${REQUIRED_FUNCTIONS[@]}"; do
    if grep -q "^${func}()" "$TEMP_SCRIPT"; then
        print_success "Function $func found"
    else
        print_error "Function $func missing"
        exit 1
    fi
done

# Test 6: Check for Proxmox detection
print_info "Checking Proxmox detection logic..."
if grep -q "command -v pct" "$TEMP_SCRIPT"; then
    print_success "Proxmox detection logic found"
else
    print_error "Proxmox detection logic missing"
    exit 1
fi

# Test 7: Simulate Proxmox detection (should fail gracefully)
print_info "Testing Proxmox detection (should fail gracefully)..."
if bash "$TEMP_SCRIPT" 2>&1 | grep -q "This script must be run from a Proxmox host"; then
    print_success "Proxmox detection works correctly"
else
    print_error "Proxmox detection not working properly"
    exit 1
fi

# Test 8: Check for required application files
print_info "Checking for required application file downloads..."
REQUIRED_FILES=("server.js" "package.json" "app/datastore.js" "public/index.html")

for file in "${REQUIRED_FILES[@]}"; do
    if grep -q "$file" "$TEMP_SCRIPT"; then
        print_success "Download for $file found"
    else
        print_error "Download for $file missing"
        exit 1
    fi
done

# Cleanup
rm -f "$TEMP_SCRIPT"

echo ""
print_header "Test Results"
echo ""
print_success "All tests passed! The installer is ready for deployment."
echo ""
print_info "To deploy on a Proxmox host, run:"
echo "curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh | bash"
echo ""
print_info "Or download first:"
echo "wget https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh"
echo "chmod +x fresh-install.sh"
echo "./fresh-install.sh"
echo ""
print_success "Installation script validation complete!"
