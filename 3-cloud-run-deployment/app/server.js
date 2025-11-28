const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;
const VERSION = process.env.APP_VERSION || 'local';

app.get('/', (req, res) => {
  res.send(`Hello from Google Cloud Run! Running version: ${VERSION}`);
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});