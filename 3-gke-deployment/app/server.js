const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.send('Hello from Google Kubernetes Engine!');
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

  // Force close server after 10 seconds
  setTimeout(() => {
    console.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);