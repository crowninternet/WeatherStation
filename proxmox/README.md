# Proxmox Deployment for WeatherStation

This folder contains all the necessary files and documentation for deploying the WeatherStation application on Proxmox VE using LXC containers.

## Files

- `fresh-install-v6.sh` - Automated installation script for Proxmox (Version 6)
- `DEPLOYMENT_GUIDE.md` - Comprehensive deployment guide
- `TROUBLESHOOTING.md` - Common issues and solutions
- `README.md` - This file

## Quick Start

1. **Run the installation script** from your Proxmox host:
```bash
./fresh-install-v6.sh
```

2. **Follow the prompts** to configure your container

3. **Access your WeatherStation** at the provided IP address

## Requirements

- Proxmox VE host with LXC support
- Debian 12 template available in Proxmox
- Internet connection for downloading dependencies

## What the Script Does

The installation script will:

1. Create a new LXC container with Debian 12
2. Install Node.js 20.x
3. Download and deploy the WeatherStation application
4. Configure systemd service for auto-start
5. Set up proper permissions and security
6. Start the WeatherStation service

## Support

For detailed instructions, troubleshooting, and configuration options, see `DEPLOYMENT_GUIDE.md`.
