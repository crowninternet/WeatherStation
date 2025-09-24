#!/bin/bash

# WeatherStations Installation Script
# This script helps set up the WeatherStations application

echo "🌤️  WeatherStations Installation Script"
echo "======================================"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js 18+ first:"
    echo "   Mac: brew install node"
    echo "   Windows: Download from https://nodejs.org/"
    echo "   Linux: sudo apt install nodejs npm"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js version 18+ is required. Current version: $(node -v)"
    exit 1
fi

echo "✅ Node.js $(node -v) detected"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed"
    exit 1
fi

echo "✅ npm $(npm -v) detected"

# Install dependencies
echo "📦 Installing dependencies..."
npm install

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo "✅ Dependencies installed successfully"

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    cat > .env << EOF
# AmbientWeather API Configuration
# Get these from https://ambientweather.net/ account → API Keys
AMBIENT_API_KEY=your_api_key_here
AMBIENT_APP_KEY=your_application_key_here

# Optional: Specific station MAC addresses (comma-separated)
# Leave empty to auto-discover all stations
STATION_MACS=

# Optional: Admin token for protected endpoints (generate a secure random string)
ADMIN_TOKEN=your_secure_token_here

# Optional: Server configuration
PORT=3333
TIMEZONE=America/New_York

# Optional: Data ingestion limits
INGEST_LIMIT=200
EOF
    echo "✅ .env file created"
    echo "⚠️  Please edit .env file with your AmbientWeather API credentials"
else
    echo "✅ .env file already exists"
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file with your AmbientWeather API credentials"
echo "2. Get API keys from: https://ambientweather.net/ account → API Keys"
echo "3. Start the application:"
echo "   Development: npm run dev"
echo "   Production:  npm start"
echo ""
echo "Access the application at:"
echo "  Dashboard: http://localhost:3333"
echo "  History:   http://localhost:3333/history"
echo ""
echo "For detailed instructions, see README.md"
