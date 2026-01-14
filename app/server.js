const express = require('express');
const { Firestore } = require('@google-cloud/firestore');

const app = express();
const PORT = process.env.PORT || 8080;
const ASSETS_URL = process.env.ASSETS_URL || '';

// Initialize Firestore with connection pooling for better performance
const firestore = new Firestore({
  maxIdleChannels: 1,  // Good for low traffic
  keepAlive: true,
  grpc: {
    'grpc.keepalive_time_ms': 120000,  // Increased from 30s
    'grpc.keepalive_timeout_ms': 10000, // Increased from 5s
    'grpc.initial_reconnect_backoff_ms': 1000,
    'grpc.max_reconnect_backoff_ms': 10000,
  },
});

// Validate Firestore connection on startup
firestore.collection('_health').limit(1).get()
  .then(() => {
    console.log('✓ Firestore connection established successfully');
  })
  .catch(err => {
    console.error('✗ FATAL: Cannot connect to Firestore on startup:', err.message);
    process.exit(1);
  });

// Add comprehensive health check
let lastHealthCheck = { timestamp: 0, result: null };
const HEALTH_CHECK_CACHE_MS = 5000; // 5 seconds

app.get('/healthz', async (req, res) => {
  const now = Date.now();
  
  // Return cached result if recent
  if (now - lastHealthCheck.timestamp < HEALTH_CHECK_CACHE_MS && lastHealthCheck.result) {
    return res.status(lastHealthCheck.result.status).json(lastHealthCheck.result.data);
  }
  
  const checks = {
    firestore: false,
    memory: false,
    uptime: false
  };
  
  try {
    // Firestore check
    await firestore.collection('_health').limit(1).get();
    checks.firestore = true;
    
    // Memory check
    const used = process.memoryUsage();
    checks.memory = used.heapUsed < (used.heapTotal * 0.9);
    
    // Uptime check
    checks.uptime = process.uptime() > 0;
    
    const healthy = Object.values(checks).every(v => v);
    
    lastHealthCheck = {
      timestamp: now,
      result: { status: healthy ? 200 : 503, data: { status: healthy ? 'healthy' : 'unhealthy', checks } }
    };
    
    res.status(lastHealthCheck.result.status).json(lastHealthCheck.result.data);
  } catch (err) {
    console.error('Health check failed:', err);
    lastHealthCheck = {
      timestamp: now,
      result: { status: 503, data: { status: 'unhealthy', checks, error: err.message } }
    };
    res.status(503).json(lastHealthCheck.result.data);
  }
});

app.get('/', async (req, res) => {
  let count = 0;
  let firestoreAvailable = true;

  try {
    const docRef = firestore.collection('visits').doc('counter');
    const doc = await docRef.get();

    if (doc.exists) {
      count = doc.data().val + 1;
      await docRef.update({ val: count });
    } else {
      count = 1;
      await docRef.set({ val: count });
    }
  } catch (err) {
    console.error('Firestore error:', err);
    firestoreAvailable = false;
    count = "unavailable";
    // Don't return 500, continue with degraded service
  }

  const html = `
    <html>
      <head><title>Containerized App</title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 2rem;">
        <h1>Hello from a containerized application!</h1>
        <p>Visitor Count: <strong>${count}</strong></p>
        ${!firestoreAvailable ? '<p><em>Counter temporarily unavailable</em></p>' : ''}
        <hr/>
        <p>
          Static Asset Test: 
          <a href="${ASSETS_URL}/message.txt" target="_blank">View message.txt from GCS</a>
        </p>
      </body>
    </html>
  `;
  
  res.send(html);
});

const server = app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});

// Implement graceful shutdown
const gracefulShutdown = () => {
  // GKE termination grace period is 30s by default
  // We give 25s for graceful shutdown to allow 5s buffer
  const DEFAULT_TIMEOUT = 25000;
  let SHUTDOWN_TIMEOUT = parseInt(process.env.SHUTDOWN_TIMEOUT || '25000', 10);

  if (isNaN(SHUTDOWN_TIMEOUT) || SHUTDOWN_TIMEOUT <= 0) {
    console.warn(`Invalid SHUTDOWN_TIMEOUT value: ${process.env.SHUTDOWN_TIMEOUT}, using default ${DEFAULT_TIMEOUT}ms`);
    SHUTDOWN_TIMEOUT = DEFAULT_TIMEOUT;
  }

  console.log(`Received kill signal, shutting down gracefully (${SHUTDOWN_TIMEOUT}ms timeout).`);
  server.close(() => {
    console.log('Closed out remaining connections.');
    process.exit(0);
  });

  setTimeout(() => {
    console.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, SHUTDOWN_TIMEOUT);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);