const express = require('express');
const router = express.Router();
const datastore = require('../datastore');
const { createClient, normalizeObservation } = require('../ambientClient');

/**
 * Resolve station name from MAC address
 */
function resolveStationName(mac, latestObservation) {
  const map = {
    '48:E7:29:7C:5F:90': 'Property',
    'C8:C9:A3:26:46:28': 'SolarShed73'
  };
  return map[mac] || (latestObservation && (latestObservation.info?.name || latestObservation.stationtype)) || null;
}

/**
 * Core ingestion function that can be called from API endpoint or automatically
 * @param {boolean} requireToken - Whether to require admin token validation
 * @returns {Object} Summary of ingestion results
 */
async function performIngestion(requireToken = true) {
  try {
    console.log('Starting data ingestion...');
    
    const client = createClient();
    const ingestLimit = parseInt(process.env.INGEST_LIMIT) || 200;
    
    // Determine station list
    let stationMacs = [];
    
    if (process.env.STATION_MACS) {
      // Use configured station MACs
      stationMacs = process.env.STATION_MACS.split(',').map(mac => mac.trim()).filter(Boolean);
      console.log(`Using configured stations: ${stationMacs.join(', ')}`);
    } else {
      // Discover stations via API
      console.log('Discovering stations via API...');
      const devices = await client.getDevices();
      stationMacs = devices.map(device => device.mac || device.macAddress);
      console.log(`Discovered ${stationMacs.length} stations`);
    }
    
    if (stationMacs.length === 0) {
      throw new Error('No stations configured or discovered');
    }
    
    let totalStationsProcessed = 0;
    let totalReadingsInserted = 0;
    let totalReadingsUpdated = 0;
    
    // Process each station
    for (const stationMac of stationMacs) {
      try {
        console.log(`Processing station ${stationMac}...`);
        
        // Get recent observations
        const observations = await client.getRecentObservations(stationMac, {
          limit: ingestLimit
        });
        
        if (observations.length === 0) {
          console.log(`No observations found for station ${stationMac}`);
          continue;
        }
        
        // Normalize observations
        const normalizedReadings = observations.map(obs => 
          normalizeObservation(obs, stationMac)
        );
        
        // Upsert readings
        const result = await datastore.upsertReadings(stationMac, normalizedReadings);
        
        // Update station metadata
        const latestObservation = observations[0]; // Most recent
        await datastore.upsertStation({
          mac: stationMac,
          name: resolveStationName(stationMac, latestObservation),
          lastSeenUTC: latestObservation.dateutc || new Date().toISOString()
        });
        
        totalStationsProcessed++;
        totalReadingsInserted += result.inserted;
        totalReadingsUpdated += result.updated;
        
        console.log(`Station ${stationMac}: ${result.inserted} inserted, ${result.updated} updated`);
        
      } catch (stationError) {
        console.error(`Error processing station ${stationMac}:`, stationError.message);
        // Continue with other stations
      }
    }
    
    // Update last ingest timestamp
    await datastore.updateLastIngest();
    
    const summary = {
      stationsProcessed: totalStationsProcessed,
      readingsInserted: totalReadingsInserted,
      readingsUpdated: totalReadingsUpdated,
      timestamp: new Date().toISOString()
    };
    
    console.log('Ingestion completed:', summary);
    return summary;
    
  } catch (error) {
    console.error('Error during ingestion:', error);
    throw error;
  }
}

/**
 * GET /tasks/ingest
 * Protected ingestion endpoint that fetches data from AmbientWeather API
 */
router.get('/ingest', async (req, res) => {
  try {
    const { token } = req.query;
    const adminToken = process.env.ADMIN_TOKEN;
    
    // Validate admin token
    if (!adminToken) {
      return res.status(500).json({ error: 'ADMIN_TOKEN not configured' });
    }
    
    if (!token || token !== adminToken) {
      return res.status(403).json({ error: 'Invalid or missing admin token' });
    }
    
    const summary = await performIngestion(true);
    res.json(summary);
    
  } catch (error) {
    console.error('Error during ingestion:', error);
    res.status(500).json({ error: 'Ingestion failed', details: error.message });
  }
});

module.exports = {
  router,
  performIngestion
};
