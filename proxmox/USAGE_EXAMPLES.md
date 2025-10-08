# WeatherStation Proxmox Installer - Usage Examples

## 🚀 Quick Installation from GitHub

### Method 1: Direct Download and Execute
```bash
# Download and run the installer directly from GitHub
curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install-v5.sh | bash
```

### Method 2: Download First, Then Execute
```bash
# Download the script to your Proxmox host
wget https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install-v5.sh

# Make it executable
chmod +x fresh-install-v5.sh

# Run the installer
./fresh-install-v5.sh
```

### Method 3: Clone Repository (if you need multiple files)
```bash
# Clone the entire repository
git clone https://github.com/crowninternet/WeatherStation.git
cd WeatherStation/proxmox

# Run the installer
./fresh-install-v5.sh
```

## 📋 Installation Process

When you run the installer, you'll be prompted for:

1. **Container ID** (e.g., 100)
2. **Hostname** (default: weatherstation)
3. **Disk size in GB** (default: 4)
4. **RAM in MB** (default: 512)
5. **Storage pool** (default: local-lxc)

### Example Installation Session:
```bash
$ ./fresh-install-v5.sh

================================
WeatherStation - Fresh Install
================================

Enter container ID (e.g., 100): 101
Enter hostname [weatherstation]: my-weather-station
Enter disk size in GB [4]: 8
Enter RAM in MB [512]: 1024
Enter storage pool [local-lxc]: local-lvm

⚠️  This will create container 101 with:
  Hostname: my-weather-station
  Disk: 8GB
  RAM: 1024MB
  Storage: local-lvm

Continue? (y/N): y

================================
Step 1: Creating LXC Container
================================
...
```

## 🔧 Post-Installation Configuration

After installation, you'll need to configure your AmbientWeather API credentials:

### 1. Create Environment File
```bash
# Enter the container
pct enter 101

# Create .env file with your credentials
cat > /opt/weatherstation/.env << 'EOF'
AMBIENT_API_KEY=your_api_key_here
AMBIENT_APP_KEY=your_application_key_here
ADMIN_TOKEN=your_secure_token_here
PORT=3333
TIMEZONE=America/New_York
INGEST_LIMIT=200
EOF

# Set proper permissions
chown weatherstation:weatherstation /opt/weatherstation/.env
chmod 600 /opt/weatherstation/.env

# Restart the service
systemctl restart weatherstation

# Exit container
exit
```

### 2. Trigger Initial Data Ingestion
```bash
# Get container IP
CONTAINER_IP=$(pct exec 101 -- hostname -I | awk '{print $1}')

# Trigger data ingestion
curl "http://$CONTAINER_IP:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN"
```

## 🌐 Access Your WeatherStation

Once configured, access your WeatherStation at:
- **Main Dashboard**: `http://CONTAINER_IP:3333`
- **Health Check**: `http://CONTAINER_IP:3333/health`
- **Historical Charts**: `http://CONTAINER_IP:3333/history`

## 🛠️ Management Commands

### Service Management
```bash
# Check status
pct exec 101 -- systemctl status weatherstation

# View logs
pct exec 101 -- journalctl -u weatherstation -f

# Restart service
pct exec 101 -- systemctl restart weatherstation
```

### Container Management
```bash
# Start container
pct start 101

# Stop container
pct stop 101

# Enter container
pct enter 101
```

## 🔍 Troubleshooting

### Check Installation Status
```bash
# Verify service is running
pct exec 101 -- systemctl is-active weatherstation

# Check if port is listening
pct exec 101 -- netstat -tlnp | grep 3333

# View recent logs
pct exec 101 -- journalctl -u weatherstation --since "10 minutes ago"
```

### Common Issues

1. **Service won't start**: Check logs with `journalctl -u weatherstation`
2. **No data showing**: Verify API credentials in `.env` file
3. **Port not accessible**: Check container networking and firewall rules

## 📚 Additional Resources

- [Complete Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Main WeatherStation README](../README.md)
- [Proxmox Documentation](https://pve.proxmox.com/wiki/Main_Page)

## 🔐 Security Notes

- The installer creates an unprivileged container for better security
- Resource limits prevent resource exhaustion
- Systemd security restrictions are applied
- Keep your `.env` file secure with proper permissions (600)

## 🚀 Automation Examples

### Automated Installation Script
```bash
#!/bin/bash
# Auto-install WeatherStation on Proxmox

# Download and run installer
curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh | bash << 'EOF'
100
weatherstation
4
512
local-lxc
y
EOF

# Wait for installation to complete
sleep 30

# Get container IP
CONTAINER_IP=$(pct exec 100 -- hostname -I | awk '{print $1}')

echo "WeatherStation installed successfully!"
echo "Access at: http://$CONTAINER_IP:3333"
echo "Remember to configure your .env file with API credentials"
```

### Docker Alternative (for non-Proxmox environments)
```bash
# If you're not using Proxmox, you can still use Docker
docker run -d \
  --name weatherstation \
  -p 3333:3333 \
  -v $(pwd)/data:/opt/weatherstation/data \
  -e AMBIENT_API_KEY=your_key \
  -e AMBIENT_APP_KEY=your_app_key \
  node:20-alpine sh -c "
    apk add --no-cache git &&
    git clone https://github.com/crowninternet/WeatherStation.git /app &&
    cd /app &&
    npm install &&
    npm start
  "
```
