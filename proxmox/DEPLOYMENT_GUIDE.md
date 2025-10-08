# WeatherStation Proxmox Deployment Guide

This guide provides comprehensive instructions for deploying the WeatherStation application on Proxmox VE using LXC containers.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Manual Installation](#manual-installation)
- [Configuration](#configuration)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Backup and Recovery](#backup-and-recovery)

## Prerequisites

### Proxmox Host Requirements

- Proxmox VE 7.0 or higher
- LXC support enabled
- Internet connectivity
- At least 1GB free RAM
- At least 8GB free storage

### Required Templates

You need a Debian 12 template in your Proxmox storage:

```bash
# Download Debian 12 template
pveam download local debian-12-standard

# List available templates
pveam list local
```

## Quick Installation

The fastest way to deploy WeatherStation is using the automated installation script:

```bash
# Download and run the installation script
wget https://raw.githubusercontent.com/crowninternet/WeatherStation/main/proxmox/fresh-install.sh
chmod +x fresh-install.sh
./fresh-install.sh
```

Follow the prompts to:
1. Enter container ID (e.g., 100)
2. Set hostname (default: weatherstation)
3. Configure disk size (default: 4GB)
4. Set RAM allocation (default: 512MB)
5. Choose storage pool (default: local-lxc)

## Manual Installation

If you prefer manual installation or need to customize the process:

### Step 1: Create LXC Container

```bash
# Create container with Debian 12
pct create 100 \
    local:vztmpl/debian-12-standard_20231010-1_amd64.tar.zst \
    --hostname weatherstation \
    --memory 512 \
    --rootfs local-lxc:4 \
    --cores 1 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --features nesting=1 \
    --unprivileged 1 \
    --onboot 1

# Start the container
pct start 100
```

### Step 2: Install Base System

```bash
# Update package list
pct exec 100 -- apt-get update

# Install base packages
pct exec 100 -- apt-get install -y curl wget ca-certificates gnupg
```

### Step 3: Install Node.js

```bash
# Add NodeSource repository
pct exec 100 -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"

# Install Node.js
pct exec 100 -- apt-get install -y nodejs

# Verify installation
pct exec 100 -- node --version
```

### Step 4: Create Application User

```bash
# Create dedicated user
pct exec 100 -- useradd -r -m -s /bin/bash weatherstation
```

### Step 5: Deploy WeatherStation

```bash
# Create application directory
pct exec 100 -- mkdir -p /opt/weatherstation
pct exec 100 -- mkdir -p /opt/weatherstation/{app/{routes,utils},public/assets,data}

# Download application files
pct exec 100 -- bash -c "cd /opt/weatherstation && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/server.js -o server.js"
pct exec 100 -- bash -c "cd /opt/weatherstation && curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/package.json -o package.json"

# Download all application files (see fresh-install.sh for complete list)
# ... (download all required files)

# Install dependencies
pct exec 100 -- bash -c "cd /opt/weatherstation && npm install --production"

# Set permissions
pct exec 100 -- chown -R weatherstation:weatherstation /opt/weatherstation
pct exec 100 -- chmod -R 755 /opt/weatherstation
```

### Step 6: Configure systemd Service

```bash
# Create service file
pct exec 100 -- bash -c "cat > /etc/systemd/system/weatherstation.service << 'EOF'
[Unit]
Description=WeatherStation - AmbientWeather Viewer & Archiver
After=network.target

[Service]
Type=simple
User=weatherstation
Group=weatherstation
WorkingDirectory=/opt/weatherstation
ExecStart=/usr/bin/node /opt/weatherstation/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3333

[Install]
WantedBy=multi-user.target
EOF"

# Enable and start service
pct exec 100 -- systemctl daemon-reload
pct exec 100 -- systemctl enable weatherstation
pct exec 100 -- systemctl start weatherstation
```

## Configuration

### Environment Configuration

Create a `.env` file with your AmbientWeather API credentials:

```bash
# Enter the container
pct enter 100

# Create environment file
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

# Exit container
exit
```

### Getting AmbientWeather API Credentials

1. Go to [AmbientWeather.net](https://ambientweather.net/)
2. Create an account or log in
3. Navigate to **Account** → **API Keys**
4. Generate a new API Key and Application Key
5. Copy these keys to your `.env` file

### Initial Data Setup

After configuration, trigger initial data ingestion:

```bash
# Get container IP
CONTAINER_IP=$(pct exec 100 -- hostname -I | awk '{print $1}')

# Trigger data ingestion
curl "http://$CONTAINER_IP:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN"
```

## Management

### Service Management

```bash
# Check service status
pct exec 100 -- systemctl status weatherstation

# Start service
pct exec 100 -- systemctl start weatherstation

# Stop service
pct exec 100 -- systemctl stop weatherstation

# Restart service
pct exec 100 -- systemctl restart weatherstation

# View logs
pct exec 100 -- journalctl -u weatherstation -f
```

### Container Management

```bash
# Enter container
pct enter 100

# Stop container
pct stop 100

# Start container
pct start 100

# Reboot container
pct reboot 100

# Destroy container (WARNING: This will delete all data)
pct destroy 100
```

### Application Updates

To update the WeatherStation application:

```bash
# Enter container
pct enter 100

# Stop service
systemctl stop weatherstation

# Backup current installation
cp -r /opt/weatherstation /opt/weatherstation.backup

# Download updated files (repeat for all files)
curl -fsSL https://raw.githubusercontent.com/crowninternet/WeatherStation/main/server.js -o /opt/weatherstation/server.js

# Update dependencies if package.json changed
cd /opt/weatherstation && npm install --production

# Set permissions
chown -R weatherstation:weatherstation /opt/weatherstation

# Start service
systemctl start weatherstation

# Exit container
exit
```

## Troubleshooting

### Common Issues

#### Service Won't Start

```bash
# Check service status
pct exec 100 -- systemctl status weatherstation

# View detailed logs
pct exec 100 -- journalctl -u weatherstation -n 50

# Check for port conflicts
pct exec 100 -- netstat -tlnp | grep 3333
```

#### No Data Showing

1. **Check API credentials**:
   ```bash
   pct exec 100 -- cat /opt/weatherstation/.env
   ```

2. **Verify network connectivity**:
   ```bash
   pct exec 100 -- curl -I https://api.ambientweather.net
   ```

3. **Check data ingestion**:
   ```bash
   # Manual data ingestion
   curl "http://CONTAINER_IP:3333/tasks/ingest?token=YOUR_TOKEN"
   ```

#### High Resource Usage

```bash
# Monitor resource usage
pct exec 100 -- top
pct exec 100 -- free -h
pct exec 100 -- df -h

# Check systemd resource limits
pct exec 100 -- systemctl show weatherstation | grep -E "(MemoryMax|CPUQuota)"
```

### Log Analysis

```bash
# View recent logs
pct exec 100 -- journalctl -u weatherstation --since "1 hour ago"

# View logs with timestamps
pct exec 100 -- journalctl -u weatherstation -o short-iso

# Follow logs in real-time
pct exec 100 -- journalctl -u weatherstation -f
```

### Network Issues

```bash
# Check container networking
pct exec 100 -- ip addr show
pct exec 100 -- ip route show

# Test connectivity
pct exec 100 -- ping -c 3 8.8.8.8
pct exec 100 -- curl -I http://localhost:3333/health
```

## Security Considerations

### Container Security

- The container runs as unprivileged for better security
- Resource limits prevent resource exhaustion
- Systemd security restrictions are applied

### Application Security

- Keep your `.env` file secure (600 permissions)
- Use strong admin tokens
- Regularly update the application
- Monitor logs for suspicious activity

### Network Security

- Consider using a reverse proxy (nginx, Apache) for SSL termination
- Implement firewall rules to restrict access
- Use VPN or private networks when possible

### Example nginx Reverse Proxy

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://CONTAINER_IP:3333;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Backup and Recovery

### Data Backup

```bash
# Backup application data
pct exec 100 -- tar -czf /tmp/weatherstation-backup.tar.gz -C /opt/weatherstation data .env

# Copy backup to host
pct pull 100 /tmp/weatherstation-backup.tar.gz /var/lib/vz/dump/

# Backup container configuration
vzdump 100 --storage local --mode snapshot
```

### Data Recovery

```bash
# Restore from backup
pct push 100 /var/lib/vz/dump/weatherstation-backup.tar.gz /tmp/
pct exec 100 -- tar -xzf /tmp/weatherstation-backup.tar.gz -C /opt/weatherstation
pct exec 100 -- chown -R weatherstation:weatherstation /opt/weatherstation
pct exec 100 -- systemctl restart weatherstation
```

### Container Migration

```bash
# Create backup
vzdump 100 --storage local --mode snapshot

# Restore on new Proxmox host
qm restore 100 /var/lib/vz/dump/vzdump-lxc-100-YYYY-MM-DD.tar.gz --storage local-lxc
```

## Performance Tuning

### Resource Optimization

```bash
# Adjust container resources
pct set 100 --memory 1024 --cores 2

# Monitor performance
pct exec 100 -- htop
pct exec 100 -- iotop
```

### Application Optimization

- Adjust `INGEST_LIMIT` in `.env` based on your data volume
- Monitor memory usage and adjust container limits
- Consider using SSD storage for better I/O performance

## Monitoring

### Health Checks

```bash
# Automated health check script
#!/bin/bash
CONTAINER_IP=$(pct exec 100 -- hostname -I | awk '{print $1}')
if curl -s "http://$CONTAINER_IP:3333/health" > /dev/null; then
    echo "WeatherStation is healthy"
else
    echo "WeatherStation is down - restarting"
    pct exec 100 -- systemctl restart weatherstation
fi
```

### Log Monitoring

Set up log monitoring to track:
- Service restarts
- API errors
- Data ingestion failures
- Resource usage spikes

## Support

For additional support:

1. Check the main [WeatherStation README](../README.md)
2. Review Proxmox documentation
3. Check application logs for error messages
4. Verify AmbientWeather API credentials
5. Ensure network connectivity

## License

This deployment guide is part of the WeatherStation project and follows the same MIT license.
