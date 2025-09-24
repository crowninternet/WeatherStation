require('dotenv').config();
const express = require('express');
const path = require('path');
const datastore = require('./app/datastore');

// Import routes
const apiRoutes = require('./app/routes/api');
const taskRoutes = require('./app/routes/tasks');

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
  });
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n=== Shutting down gracefully ===');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n=== Shutting down gracefully ===');
  process.exit(0);
});

// Start the server
startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
