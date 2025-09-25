require('dotenv').config();
const express = require('express');
const path = require('path');
const datastore = require('./app/datastore');

// Import routes
const apiRoutes = require('./app/routes/api');
const { router: taskRoutes, performIngestion } = require('./app/routes/tasks');

const app = express();
const PORT = process.env.PORT || 3333;

// Global error handlers for uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  console.error('Stack:', error.stack);
  // Don't exit immediately, log and continue
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit immediately, log and continue
});

// Keep process alive
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
});

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

// Start server with better error handling
async function startServer() {
  try {
    await initializeApp();
    
    const server = app.listen(PORT, () => {
      console.log('=== Server Started ===');
      console.log(`🌐 Dashboard: http://localhost:${PORT}`);
      console.log(`📊 History: http://localhost:${PORT}/history`);
      console.log(`🔧 API: http://localhost:${PORT}/api/stations`);
      console.log(`⚡ Ingest: http://localhost:${PORT}/tasks/ingest?token=YOUR_TOKEN`);
      console.log('========================');
      
      // Start automatic data refresh every 5 minutes
      startAutomaticRefresh();
    });

    // Handle server errors
    server.on('error', (error) => {
      if (error.code === 'EADDRINUSE') {
        console.error(`Port ${PORT} is already in use. Trying to find and kill existing process...`);
        // Try to find and kill the process using the port
        require('child_process').exec(`lsof -ti:${PORT}`, (err, stdout) => {
          if (stdout) {
            const pid = stdout.trim();
            console.log(`Killing process ${pid} using port ${PORT}`);
            process.kill(pid, 'SIGTERM');
            setTimeout(() => {
              console.log('Retrying server start...');
              startServer();
            }, 2000);
          } else {
            console.error('Could not find process using port', PORT);
            process.exit(1);
          }
        });
      } else {
        console.error('Server error:', error);
        process.exit(1);
      }
    });

    // Graceful shutdown
    const gracefulShutdown = () => {
      console.log('Shutting down server gracefully...');
      server.close(() => {
        console.log('Server closed');
        stopAutomaticRefresh();
        process.exit(0);
      });
    };

    process.on('SIGTERM', gracefulShutdown);
    process.on('SIGINT', gracefulShutdown);

  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
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
      console.error('Error stack:', error.stack);
      // Don't let ingestion errors crash the server
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
    console.error('Error stack:', error.stack);
    // Don't let initial ingestion failure crash the server
  }
}

function stopAutomaticRefresh() {
  if (refreshInterval) {
    clearInterval(refreshInterval);
    refreshInterval = null;
    console.log('🛑 Automatic data refresh stopped');
  }
}

// Remove duplicate signal handlers (moved to startServer function)

// Start the server
startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
