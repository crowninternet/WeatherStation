const fs = require('fs').promises;
const path = require('path');
const Mutex = require('./mutex');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DATA_FILE = path.join(DATA_DIR, 'data.json');
const TEMP_FILE = path.join(DATA_DIR, 'data.tmp');

const mutex = new Mutex();

/**
 * Ensure the data directory and file exist with proper structure
 */
async function ensureFile() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
    
    try {
      await fs.access(DATA_FILE);
    } catch (error) {
      // File doesn't exist, create it with empty structure
      const emptyData = {
        meta: {
          version: 1,
          timezone: process.env.TIMEZONE || 'UTC',
          lastIngestISO: null
        },
        stations: {},
        readings: []
      };
      
      await fs.writeFile(DATA_FILE, JSON.stringify(emptyData, null, 2));
      console.log('Created initial data.json file');
    }
  } catch (error) {
    console.error('Error ensuring data file:', error);
    throw error;
  }
}

/**
 * Read the datastore from disk
 */
async function readStore() {
  try {
    const data = await fs.readFile(DATA_FILE, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error('Error reading datastore:', error);
    
    // Try to backup corrupted file and restore from empty structure
    try {
      const backupFile = `${DATA_FILE}.backup.${Date.now()}`;
      await fs.copyFile(DATA_FILE, backupFile);
      console.log(`Backed up corrupted file to ${backupFile}`);
      
      await ensureFile();
      return await readStore();
    } catch (backupError) {
      console.error('Failed to backup and restore:', backupError);
      throw error;
    }
  }
}

/**
 * Write the datastore to disk atomically
 */
async function writeStore(nextObj) {
  await mutex.acquire();
  
  try {
    // Write to temporary file first
    await fs.writeFile(TEMP_FILE, JSON.stringify(nextObj, null, 2));
    
    // Atomic rename
    await fs.rename(TEMP_FILE, DATA_FILE);
  } catch (error) {
    console.error('Error writing datastore:', error);
    throw error;
  } finally {
    mutex.release();
  }
}

/**
 * Upsert a station record
 */
async function upsertStation({ mac, name, lastSeenUTC }) {
  const store = await readStore();
  
  if (!store.stations[mac]) {
    store.stations[mac] = { mac, name: null, lastSeenUTC: null };
  }
  
  if (name !== undefined) store.stations[mac].name = name;
  if (lastSeenUTC !== undefined) store.stations[mac].lastSeenUTC = lastSeenUTC;
  
  await writeStore(store);
  return store.stations[mac];
}

/**
 * Upsert readings for a station, enforcing uniqueness on (station_mac, observed_utc)
 */
async function upsertReadings(stationMac, readings) {
  const store = await readStore();
  
  // Create a map of existing readings for quick lookup
  const existingMap = new Map();
  store.readings.forEach(reading => {
    const key = `${reading.station_mac}|${reading.observed_utc}`;
    existingMap.set(key, reading);
  });
  
  let inserted = 0;
  let updated = 0;
  
  readings.forEach(reading => {
    const key = `${reading.station_mac}|${reading.observed_utc}`;
    
    if (existingMap.has(key)) {
      // Update existing reading
      const existingIndex = store.readings.findIndex(r => 
        r.station_mac === reading.station_mac && r.observed_utc === reading.observed_utc
      );
      store.readings[existingIndex] = reading;
      updated++;
    } else {
      // Insert new reading
      store.readings.push(reading);
      inserted++;
    }
  });
  
  // Sort readings by observed_utc for better performance
  store.readings.sort((a, b) => new Date(a.observed_utc) - new Date(b.observed_utc));
  
  await writeStore(store);
  
  return { inserted, updated };
}

/**
 * Get the latest reading for a station
 */
async function getLatestReading(stationMac) {
  const store = await readStore();
  
  const stationReadings = store.readings
    .filter(reading => reading.station_mac === stationMac)
    .sort((a, b) => new Date(b.observed_utc) - new Date(a.observed_utc));
  
  return stationReadings.length > 0 ? stationReadings[0] : null;
}

/**
 * Query readings with optional filters
 */
async function queryReadings({ stationMac, metric, from, to }) {
  const store = await readStore();
  
  let filteredReadings = store.readings;
  
  if (stationMac) {
    filteredReadings = filteredReadings.filter(r => r.station_mac === stationMac);
  }
  
  if (from) {
    const fromDate = new Date(from);
    filteredReadings = filteredReadings.filter(r => new Date(r.observed_utc) >= fromDate);
  }
  
  if (to) {
    const toDate = new Date(to);
    filteredReadings = filteredReadings.filter(r => new Date(r.observed_utc) <= toDate);
  }
  
  // If metric is specified, only return readings that have that metric
  if (metric) {
    filteredReadings = filteredReadings.filter(r => r[metric] !== undefined && r[metric] !== null);
  }
  
  return filteredReadings;
}

/**
 * Compute daily aggregates for a set of readings
 */
function computeDaily(readings, metric) {
  const dailyMap = new Map();
  
  readings.forEach(reading => {
    const dayISO = reading.observed_utc.split('T')[0]; // Extract YYYY-MM-DD
    const value = reading[metric];
    
    if (value === undefined || value === null) return;
    
    if (!dailyMap.has(dayISO)) {
      dailyMap.set(dayISO, {
        values: [],
        count: 0,
        sum: 0,
        min: value,
        max: value
      });
    }
    
    const dayData = dailyMap.get(dayISO);
    dayData.values.push(value);
    dayData.count++;
    dayData.sum += value;
    dayData.min = Math.min(dayData.min, value);
    dayData.max = Math.max(dayData.max, value);
  });
  
  // Convert to array of daily aggregates
  const dailyAggregates = [];
  
  dailyMap.forEach((dayData, dayISO) => {
    const avg = dayData.sum / dayData.count;
    
    // For different metrics, choose appropriate aggregation
    let aggregatedValue;
    if (metric.includes('rain') || metric.includes('solar') || metric.includes('uv')) {
      // Sum for cumulative metrics
      aggregatedValue = dayData.sum;
    } else {
      // Average for most other metrics
      aggregatedValue = avg;
    }
    
    dailyAggregates.push({
      day: dayISO,
      value: aggregatedValue,
      min: dayData.min,
      max: dayData.max,
      count: dayData.count
    });
  });
  
  return dailyAggregates.sort((a, b) => a.day.localeCompare(b.day));
}

/**
 * Update the last ingest timestamp
 */
async function updateLastIngest() {
  const store = await readStore();
  store.meta.lastIngestISO = new Date().toISOString();
  await writeStore(store);
}

module.exports = {
  ensureFile,
  readStore,
  writeStore,
  upsertStation,
  upsertReadings,
  getLatestReading,
  queryReadings,
  computeDaily,
  updateLastIngest
};




