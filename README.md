# WeatherStations - AmbientWeather Viewer & Archiver

A Node.js web application that displays current weather conditions and historical charts from AmbientWeather stations.

## Features

- 📊 Real-time weather dashboard
- 📈 Historical data charts
- 🔄 Automatic data ingestion from AmbientWeather API
- 📱 Responsive web interface
- 🔒 Secure API endpoints with token authentication

## Prerequisites

- **Node.js** version 18.0.0 or higher
- **npm** (comes with Node.js)
- **AmbientWeather API credentials** (API Key and Application Key)

### Installing Node.js

#### On Mac:
```bash
# Using Homebrew (recommended)
brew install node

# Or download from https://nodejs.org/
```

#### On Windows:
1. Download Node.js from https://nodejs.org/
2. Run the installer and follow the setup wizard
3. Verify installation: `node --version` and `npm --version`

#### On Linux (Ubuntu/Debian):
```bash
# Update package index
sudo apt update

# Install Node.js
sudo apt install nodejs npm

# Verify installation
node --version
npm --version
```

## Installation Instructions

### 1. Clone the Repository

```bash
# Clone the repository
git clone https://github.com/crowninternet/WeatherStation.git

# Navigate to the project directory
cd WeatherStation
```

### 2. Install Dependencies

```bash
# Install all required packages
npm install
```

### 3. Environment Configuration

Create a `.env` file in the project root directory:

```bash
# Create the environment file
touch .env
```

Add the following configuration to your `.env` file:

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

### 4. Get AmbientWeather API Credentials

1. Go to [AmbientWeather.net](https://ambientweather.net/)
2. Create an account or log in
3. Navigate to **Account** → **API Keys**
4. Generate a new API Key and Application Key
5. Copy these keys to your `.env` file

### 5. Start the Application

#### Development Mode (with auto-restart):
```bash
npm run dev
```

#### Production Mode:
```bash
npm start
```

### 6. Access the Application

Once started, the application will be available at:

- **Main Dashboard**: http://localhost:3333
- **Historical Charts**: http://localhost:3333/history
- **API Endpoints**: http://localhost:3333/api/stations
- **Health Check**: http://localhost:3333/health

## Usage

### Initial Data Setup

1. **Start the application** using `npm start` or `npm run dev`
2. **Trigger data ingestion** by visiting:
   ```
   http://localhost:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN
   ```
   Replace `YOUR_ADMIN_TOKEN` with the token you set in your `.env` file.

3. **View the dashboard** at http://localhost:3333 to see current weather data
4. **Check historical charts** at http://localhost:3333/history

### Automatic Data Updates

The application automatically fetches new data every 5 minutes when running. For production deployments, you can set up the application as a system service:

#### macOS Service Setup (Optional)

1. **Copy the template plist file**:
   ```bash
   cp com.weatherstations.server.plist.template com.weatherstations.server.plist
   ```

2. **Edit the plist file** to replace `REPLACE_WITH_YOUR_PROJECT_PATH` with your actual project path:
   ```bash
   # Replace all instances of REPLACE_WITH_YOUR_PROJECT_PATH with your actual path
   sed -i '' 's|REPLACE_WITH_YOUR_PROJECT_PATH|/Users/yourusername/Documents/WeatherStation|g' com.weatherstations.server.plist
   ```

3. **Install the service**:
   ```bash
   cp com.weatherstations.server.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.weatherstations.server.plist
   ```

4. **Manage the service**:
   ```bash
   # Check status
   launchctl list | grep weatherstations
   
   # Unload service
   launchctl unload ~/Library/LaunchAgents/com.weatherstations.server.plist
   ```

#### Manual Cron Job (Alternative)

Set up a cron job to call the ingest endpoint periodically:

```bash
# Example cron job (runs every 5 minutes)
*/5 * * * * curl "http://localhost:3333/tasks/ingest?token=YOUR_ADMIN_TOKEN"
```

## Project Structure

```
WeatherStation/
├── app/
│   ├── routes/          # API and task routes
│   ├── utils/           # Utility functions
│   ├── ambientClient.js # AmbientWeather API client
│   ├── datastore.js     # Data storage management
│   └── mutex.js         # Concurrency control
├── public/
│   ├── assets/          # CSS and JavaScript files
│   ├── index.html       # Main dashboard
│   └── history.html     # Historical charts
├── data/
│   └── data.json        # Weather data storage
├── server.js            # Main application server
├── package.json         # Dependencies and scripts
└── .env                 # Environment configuration
```

## API Endpoints

### Public Endpoints
- `GET /api/stations` - Get current weather data for all stations
- `GET /api/stations/:mac` - Get data for specific station
- `GET /health` - Health check endpoint

### Protected Endpoints (require admin token)
- `POST /tasks/ingest` - Trigger data ingestion from AmbientWeather API

## Troubleshooting

### Common Issues

1. **"API Key not configured" error**
   - Ensure your `.env` file exists and contains valid API credentials
   - Check that the file is in the project root directory

2. **"Port already in use" error**
   - Change the PORT in your `.env` file to a different number (e.g., 3334)
   - Or stop other applications using port 3333

3. **No data showing on dashboard**
   - Verify your AmbientWeather API credentials are correct
   - Trigger manual data ingestion: `http://localhost:3333/tasks/ingest?token=YOUR_TOKEN`
   - Check the server logs for error messages

4. **Rate limiting errors**
   - The application includes automatic retry logic for rate limits
   - Consider reducing the frequency of data ingestion calls

### Logs and Debugging

- Check the console output for error messages
- Server logs are displayed in the terminal where you started the application
- Use `npm run dev` for development mode with auto-restart on file changes

## Security Notes

- Keep your `.env` file secure and never commit it to version control
- Use a strong, unique admin token
- The application includes CORS protection and input validation
- API endpoints are protected with token authentication

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the server logs for error messages
3. Verify your AmbientWeather API credentials
4. Ensure all dependencies are properly installed

## License

MIT License - see LICENSE file for details.
