# WeatherStation Proxmox Troubleshooting Guide

## Common Issues and Solutions

### 1. "Failed to load station data" Error

This error occurs when the WeatherStation application cannot connect to weather station hardware or lacks configuration.

#### **Root Cause:**
- Missing AmbientWeather API credentials
- No initial data has been ingested
- API credentials are incorrect

#### **Solution Steps:**

##### Step 1: Configure API Credentials
The WeatherStation needs AmbientWeather API credentials to connect to your weather stations.

1. **Get API Credentials:**
   - Go to [AmbientWeather.net](https://ambientweather.net/)
   - Create an account or log in
   - Navigate to **Account** → **API Keys**
   - Generate a new API Key and Application Key

2. **Configure the Container:**
   ```bash
   # Enter the container
   pct enter <CONTAINER_ID>
   
   # Create/edit the .env file
   nano /opt/weatherstation/.env
   ```

3. **Add your credentials to .env:**
   ```env
   # AmbientWeather API Configuration
   AMBIENT_API_KEY=your_api_key_here
   AMBIENT_APP_KEY=your_application_key_here
   
   # Optional: Specific station MAC addresses (comma-separated)
   # Leave empty to auto-discover all stations
   STATION_MACS=
   
   # Optional: Admin token for protected endpoints
   ADMIN_TOKEN=your_secure_token_here
   
   # Optional: Server configuration
   PORT=3333
   TIMEZONE=America/New_York
   
   # Optional: Data ingestion limits
   INGEST_LIMIT=200
   ```

##### Step 2: Restart the Service
```bash
# Exit the container
exit

# Restart the weatherstation service
pct exec <CONTAINER_ID> -- systemctl restart weatherstation
```

##### Step 3: Trigger Initial Data Ingestion
```bash
# Get your container IP
pct exec <CONTAINER_ID> -- ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1

# Trigger data ingestion (replace TOKEN with your admin token)
curl "http://<CONTAINER_IP>:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN"
```

##### Step 4: Verify Data Loading
```bash
# Check if stations are discovered
curl "http://<CONTAINER_IP>:3333/api/stations"

# Check service logs
pct exec <CONTAINER_ID> -- journalctl -u weatherstation -f
```

### 2. Service Won't Start

#### **Check Service Status:**
```bash
pct exec <CONTAINER_ID> -- systemctl status weatherstation
```

#### **Check Logs:**
```bash
pct exec <CONTAINER_ID> -- journalctl -u weatherstation -n 50
```

#### **Common Issues:**
- **Port already in use**: Change PORT in .env file
- **Missing dependencies**: Run `npm install` in container
- **Permission issues**: Check file ownership

### 3. No Weather Data Showing

#### **Verify API Connection:**
```bash
# Test API credentials manually
pct exec <CONTAINER_ID> -- node -e "
const client = require('./app/ambientClient');
const c = client.createClient();
c.getDevices().then(console.log).catch(console.error);
"
```

#### **Check Data File:**
```bash
# Check if data.json exists and has content
pct exec <CONTAINER_ID> -- cat /opt/weatherstation/data/data.json
```

### 4. Network/Connectivity Issues

#### **Check Container Network:**
```bash
# Verify container can reach external APIs
pct exec <CONTAINER_ID> -- ping -c 3 api.ambientweather.net
pct exec <CONTAINER_ID> -- curl -I https://api.ambientweather.net/v1/devices
```

#### **Check Firewall:**
```bash
# Ensure port 3333 is accessible
pct exec <CONTAINER_ID> -- netstat -tlnp | grep 3333
```

### 5. Performance Issues

#### **Check Resource Usage:**
```bash
# Monitor container resources
pct exec <CONTAINER_ID> -- top
pct exec <CONTAINER_ID> -- df -h
```

#### **Adjust Resource Limits:**
```bash
# Edit container configuration
nano /etc/pve/lxc/<CONTAINER_ID>.conf
```

## Quick Diagnostic Commands

### Check Application Status:
```bash
# Service status
pct exec <CONTAINER_ID> -- systemctl status weatherstation

# Recent logs
pct exec <CONTAINER_ID> -- journalctl -u weatherstation -n 20

# Check if app is responding
curl http://<CONTAINER_IP>:3333/health
```

### Verify Configuration:
```bash
# Check environment variables
pct exec <CONTAINER_ID> -- cat /opt/weatherstation/.env

# Check data directory
pct exec <CONTAINER_ID> -- ls -la /opt/weatherstation/data/

# Check file permissions
pct exec <CONTAINER_ID> -- ls -la /opt/weatherstation/
```

### Test API Connectivity:
```bash
# Test external API access
pct exec <CONTAINER_ID> -- curl -s "https://api.ambientweather.net/v1/devices?applicationKey=YOUR_APP_KEY&apiKey=YOUR_API_KEY"

# Test internal API
curl http://<CONTAINER_IP>:3333/api/stations
```

## Getting Help

If you're still experiencing issues:

1. **Collect logs**: `pct exec <CONTAINER_ID> -- journalctl -u weatherstation -n 100`
2. **Check configuration**: Verify your .env file has correct API credentials
3. **Test connectivity**: Ensure the container can reach external APIs
4. **Verify credentials**: Double-check your AmbientWeather API keys are correct and active

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `AMBIENT_API_KEY` | Yes | Your AmbientWeather API Key |
| `AMBIENT_APP_KEY` | Yes | Your AmbientWeather Application Key |
| `STATION_MACS` | No | Comma-separated list of station MAC addresses |
| `ADMIN_TOKEN` | No | Token for protected API endpoints |
| `PORT` | No | Server port (default: 3333) |
| `TIMEZONE` | No | Timezone for data (default: UTC) |
| `INGEST_LIMIT` | No | Max observations per ingestion (default: 200) |
