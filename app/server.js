const express = require('express');
const { Firestore } = require('@google-cloud/firestore');

const app = express();
const PORT = process.env.PORT || 8080;
const ASSETS_URL = process.env.ASSETS_URL || '';

// Initialize Firestore
const firestore = new Firestore();

// Add health check for Firestore
app.get('/healthz', async (req, res) => {
  try {
    await firestore.collection('_health').limit(1).get();
    res.status(200).send('OK');
  } catch (err) {
    console.error('Health check failed:', err);
    res.status(503).send('Service Unavailable');
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
  console.log('Received kill signal, shutting down gracefully.');
  server.close(() => {
    console.log('Closed out remaining connections.');
    process.exit(0);
  });

  setTimeout(() => {
    console.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 5000); // Reduce to 5000ms for faster restarts.
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);