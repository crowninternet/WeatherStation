// Use native fetch in Node.js 18+
const fetch = globalThis.fetch || require('node-fetch');

const AMBIENT_BASE_URL = 'https://rt.ambientweather.net';

/**
 * AmbientWeather API Client
 */
class AmbientWeatherClient {
  constructor(apiKey, applicationKey) {
    this.apiKey = apiKey;
    this.applicationKey = applicationKey;
  }

  /**
   * Make API request with retry logic for 429 errors
   */
  async makeRequest(url, options = {}) {
    const maxRetries = 3;
    let lastError;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        const response = await fetch(url, {
          ...options,
          headers: {
            'User-Agent': 'AmbientWeather-Viewer/1.0',
            ...options.headers
          }
        });

        if (response.status === 429) {
          // Rate limited - wait with exponential backoff + jitter
          const waitTime = Math.min(1000 * Math.pow(2, attempt) + Math.random() * 1000, 10000);
          console.log(`Rate limited, waiting ${waitTime}ms before retry ${attempt + 1}/${maxRetries}`);
          
          if (attempt < maxRetries - 1) {
            await new Promise(resolve => setTimeout(resolve, waitTime));
            continue;
          }
        }

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        return await response.json();
      } catch (error) {
        lastError = error;
        
        if (attempt < maxRetries - 1) {
          const waitTime = 500 * Math.pow(2, attempt) + Math.random() * 500;
          console.log(`Request failed, retrying in ${waitTime}ms: ${error.message}`);
          await new Promise(resolve => setTimeout(resolve, waitTime));
        }
      }
    }

    throw lastError;
  }

  /**
   * Get all devices for the account
   */
  async getDevices() {
    const url = `${AMBIENT_BASE_URL}/v1/devices?apiKey=${this.apiKey}&applicationKey=${this.applicationKey}`;
    
    try {
      const devices = await this.makeRequest(url);
      console.log(`Retrieved ${devices.length} devices from AmbientWeather API`);
      console.log('Sample device:', JSON.stringify(devices[0], null, 2));
      return devices;
    } catch (error) {
      console.error('Error fetching devices:', error.message);
      throw error;
    }
  }

  /**
   * Get recent observations for a specific device
   */
  async getRecentObservations(mac, { limit = 200, endDate = null } = {}) {
    let url = `${AMBIENT_BASE_URL}/v1/devices/${mac}?apiKey=${this.apiKey}&applicationKey=${this.applicationKey}&limit=${limit}`;
    
    if (endDate) {
      url += `&endDate=${encodeURIComponent(endDate)}`;
    }

    try {
      const observations = await this.makeRequest(url);
      console.log(`Retrieved ${observations.length} observations for device ${mac}`);
      return observations;
    } catch (error) {
      console.error(`Error fetching observations for ${mac}:`, error.message);
      throw error;
    }
  }
}

/**
 * Normalize AmbientWeather observation to our internal format
 */
function normalizeObservation(observation, stationMac) {
  const now = new Date().toISOString();
  
  return {
    station_mac: stationMac,
    observed_utc: observation.dateutc || now,
    temp_f: observation.tempf,
    humidity: observation.humidity,
    dewpoint_f: observation.dewPoint,
    pressure_in: observation.baromrelin,
    wind_mph: observation.windspeedmph,
    wind_gust_mph: observation.windgustmph,
    wind_dir_deg: observation.winddir,
    rain_hour_in: observation.hourlyrainin,
    rain_daily_in: observation.dailyrainin,
    solar_radiation: observation.solarradiation,
    uv: observation.uv,
    tempinf: observation.tempinf,
    humidityin: observation.humidityin,
    battery_ok: observation.battout === 0 ? 1 : 0, // 0 = OK, 1 = Low
    raw: observation
  };
}

/**
 * Create AmbientWeather client instance
 */
function createClient() {
  const apiKey = process.env.AMBIENT_API_KEY;
  const applicationKey = process.env.AMBIENT_APP_KEY;

  if (!apiKey || !applicationKey) {
    throw new Error('AMBIENT_API_KEY and AMBIENT_APP_KEY must be set in environment');
  }

  return new AmbientWeatherClient(apiKey, applicationKey);
}

module.exports = {
  AmbientWeatherClient,
  normalizeObservation,
  createClient
};
