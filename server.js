require('dotenv').config();
const express = require('express');
const path = require('path');
const datastore = require('./app/datastore');

// Import routes
const apiRoutes = require('./app/routes/api');
const { router: taskRoutes, performIngestion } = require('./app/routes/tasks');

const app = express();
const PORT = process.env.PORT || 3333;

// Log environment configuration (mask secrets)
console.log('=== AmbientWeather Viewer Starting ===');
console.log(`Port: ${PORT}`);
console.log(`Timezone: ${process.env.TIMEZONE || 'UTC'}`);
console.log(`API Key: ${process.env.AMBIENT_API_KEY ? '***configured***' : 'NOT SET'}`);
console.log(`App Key: ${process.env.AMBIENT_APP_KEY ? '***configured***' : 'NOT SET'}`);
console.log(`Admin Token: ${process.env.ADMIN_TOKEN ? '***configured***' : 'NOT SET'}`);
console.log(`Station MACs: ${process.env.STATION_MACS || 'Auto-discover'}`);
console.log(`Ingest Limit: ${process.env.INGEST_LIMIT || 200}`);

// Ensure data file exists on startup
async function initializeApp() {
  try {
    await datastore.ensureFile();
    console.log('✓ Data store initialized');
  } catch (error) {
    console.error('✗ Failed to initialize data store:', error);
    process.exit(1);
  }
}

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS - restrict to same origin
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', req.headers.origin || 'http://localhost:' + PORT);
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  
  if (req.method === 'OPTIONS') {
    res.sendStatus(200);
  } else {
    next();
  }
});

// Serve static files from public directory
app.use(express.static(path.join(__dirname, 'public')));

// API routes
app.use('/api', (req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.set('Pragma', 'no-cache');
  res.set('Expires', '0');
  next();
}, apiRoutes);

// Task routes (protected)
app.use('/tasks', (req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.set('Pragma', 'no-cache');
  res.set('Expires', '0');
  next();
}, taskRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// 404 handler for API routes
app.use('/api/*', (req, res) => {
  res.status(404).json({ error: 'API endpoint not found' });
});

// 404 handler for task routes
app.use('/tasks/*', (req, res) => {
  res.status(404).json({ error: 'Task endpoint not found' });
});

// Error handler
app.use((error, req, res, next) => {
  console.error('Unhandled error:', error);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
async function startServer() {
  await initializeApp();
  
  app.listen(PORT, () => {
    console.log('=== Server Started ===');
    console.log(`🌐 Dashboard: http://localhost:${PORT}`);
    console.log(`📊 History: http://localhost:${PORT}/history`);
    console.log(`🔧 API: http://localhost:${PORT}/api/stations`);
    console.log(`⚡ Ingest: http://localhost:${PORT}/tasks/ingest?token=YOUR_TOKEN`);
    console.log('========================');
    
    // Start automatic data refresh every 5 minutes
    startAutomaticRefresh();
  });
}

// Automatic data refresh functionality
let refreshInterval = null;

function startAutomaticRefresh() {
  const refreshIntervalMinutes = 5; // Refresh every 5 minutes
  const refreshIntervalMs = refreshIntervalMinutes * 60 * 1000;
  
  console.log(`🔄 Starting automatic data refresh every ${refreshIntervalMinutes} minutes`);
  
  // Perform initial ingestion on startup
  performInitialIngestion();
  
  // Set up interval for regular refreshes
  refreshInterval = setInterval(async () => {
    try {
      console.log(`🔄 [${new Date().toISOString()}] Starting scheduled data refresh...`);
      await performIngestion(false); // Don't require token for automatic refresh
      console.log(`✅ [${new Date().toISOString()}] Scheduled refresh completed successfully`);
    } catch (error) {
      console.error(`❌ [${new Date().toISOString()}] Scheduled refresh failed:`, error.message);
    }
  }, refreshIntervalMs);
}

async function performInitialIngestion() {
  try {
    console.log('🔄 Performing initial data ingestion on startup...');
    await performIngestion(false); // Don't require token for automatic refresh
    console.log('✅ Initial data ingestion completed successfully');
  } catch (error) {
    console.error('❌ Initial data ingestion failed:', error.message);
  }
}

function stopAutomaticRefresh() {
  if (refreshInterval) {
    clearInterval(refreshInterval);
    refreshInterval = null;
    console.log('🛑 Automatic data refresh stopped');
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n=== Shutting down gracefully ===');
  stopAutomaticRefresh();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n=== Shutting down gracefully ===');
  stopAutomaticRefresh();
  process.exit(0);
});

// Start the server
startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
