const express = require('express');
const router = express.Router();
const datastore = require('../datastore.js');
const { getDateRange } = require('../utils/dates.js');

// Valid metrics for filtering
const VALID_METRICS = [
  'temp_f', 'humidity', 'dewpoint_f', 'pressure_in', 
  'wind_mph', 'wind_gust_mph', 'wind_dir_deg', 
  'rain_hour_in', 'rain_daily_in', 'uv', 'solar_radiation',
  'tempinf', 'humidityin'
];

/**
 * GET /api/stations
 * Returns array of stations with metadata
 */
router.get('/stations', async (req, res) => {
  try {
    const store = await datastore.readStore();
    
    const stations = Object.values(store.stations).map(station => ({
      station_mac: station.mac,
      name: station.name,
      last_seen_utc: station.lastSeenUTC
    }));
    
    res.json(stations);
  } catch (error) {
    console.error('Error fetching stations:', error);
    res.status(500).json({ error: 'Failed to fetch stations' });
  }
});

/**
 * GET /api/readings
 * Returns filtered readings with optional downsampling
 */
router.get('/readings', async (req, res) => {
  try {
    const { station_mac, metric, from, to, downsample } = req.query;
    
    // Validate station_mac if provided
    if (station_mac) {
      const store = await datastore.readStore();
      if (!store.stations[station_mac]) {
        return res.status(400).json({ error: 'Invalid station_mac' });
      }
    }
    
    // Validate metric if provided
    if (metric && !VALID_METRICS.includes(metric)) {
      return res.status(400).json({ 
        error: 'Invalid metric', 
        validMetrics: VALID_METRICS 
      });
    }
    
    // Parse date range
    const dateRange = getDateRange(from, to);
    
    // Query readings
    const readings = await datastore.queryReadings({
      stationMac: station_mac,
      metric: metric,
      from: dateRange.from,
      to: dateRange.to
    });
    
    let result;
    
    if (downsample === 'daily' && metric) {
      // Compute daily aggregates
      const dailyData = datastore.computeDaily(readings, metric);
      result = dailyData.map(day => ({
        t: `${day.day}T00:00:00Z`,
        v: day.value,
        min: day.min,
        max: day.max,
        count: day.count
      }));
    } else {
      // Return individual readings
      result = readings.map(reading => ({
        t: reading.observed_utc,
        v: metric ? reading[metric] : reading
      }));
    }
    
    res.json(result);
  } catch (error) {
    console.error('Error fetching readings:', error);
    res.status(500).json({ error: 'Failed to fetch readings' });
  }
});

/**
 * GET /api/readings/latest
 * Returns latest reading for each station
 */
router.get('/readings/latest', async (req, res) => {
    try {
        const { station_mac } = req.query;
        
        if (station_mac) {
            // Single station
            const latest = await datastore.getLatestReading(station_mac);
            res.json(latest ? [latest] : []);
        } else {
            // All stations
            const store = await datastore.readStore();
            const latestReadings = [];
            
            for (const stationMac of Object.keys(store.stations)) {
                const latest = await datastore.getLatestReading(stationMac);
                if (latest) {
                    latestReadings.push(latest);
                }
            }
            
            res.json(latestReadings);
        }
    } catch (error) {
        console.error('Error fetching latest readings:', error);
        res.status(500).json({ error: 'Failed to fetch latest readings' });
    }
});

/**
 * GET /api/admin-token
 * Returns admin token for frontend refresh functionality
 */
router.get('/admin-token', (req, res) => {
    const token = process.env.ADMIN_TOKEN;
    if (!token) {
        return res.status(404).json({ error: 'Admin token not configured' });
    }
    res.json({ token });
});

module.exports = router;
