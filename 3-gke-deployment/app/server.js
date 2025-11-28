const express = require('express');
const { Firestore } = require('@google-cloud/firestore');

const app = express();
const PORT = process.env.PORT || 8080;
const ASSETS_URL = process.env.ASSETS_URL || '';

// Initialize Firestore
const firestore = new Firestore();

// Health check endpoint (lightweight, for probes)
app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

app.get('/', async (req, res) => {
  let count = 0;
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
  }

  const html = `
    <html>
      <head><title>GKE App</title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 2rem;">
        <h1>Hello from Google Kubernetes Engine!</h1>
        <p>Visitor Count: <strong>${count}</strong></p>
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
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);