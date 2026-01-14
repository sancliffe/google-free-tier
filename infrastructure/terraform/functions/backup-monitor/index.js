const { Storage } = require('@google-cloud/storage');
const storage = new Storage();

/**
 * Checks if backups are running daily.
 * Triggered by HTTP request or Cloud Scheduler.
 *
 * @param {object} req Cloud Function request context.
 * @param {object} res Cloud Function response context.
 */
exports.checkBackups = async (req, res) => {
  const bucketName = process.env.BACKUP_BUCKET_NAME; // The bucket where backups are stored
  const backupPrefix = process.env.BACKUP_PREFIX || 'backup-'; // Expected prefix of backup files

  if (!bucketName) {
    console.error('BACKUP_BUCKET_NAME environment variable is not set.');
    return res.status(500).send('Backup bucket name is not configured.');
  }

  try {
    const [files] = await storage.bucket(bucketName).getFiles({ 
      prefix: backupPrefix,
      maxResults: 1000  // Limit to prevent memory issues
    });
    
    if (!files || files.length === 0) {
      console.error(`No backup files found in gs://${bucketName}/${backupPrefix}`);
      return res.status(500).send('No backups found in bucket.');
    }
    
    let latestBackupTimestamp = 0;
    files.forEach(file => {
      // Assuming backup files are named like 'backup-YYYY-MM-DD-HHMMSS.tar.gz'
      // Extract timestamp from filename
      const match = file.name.match(/(\d{4}-\d{2}-\d{2}-\d{6})/);
      if (match) {
        const dateString = match[1].replace(/-/g, '').replace(/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/, '$1-$2-$3T$4:$5:$6Z');
        const timestamp = new Date(dateString).getTime();
        if (!isNaN(timestamp) && timestamp > latestBackupTimestamp) {
          latestBackupTimestamp = timestamp;
        }
      }
    });

    if (latestBackupTimestamp === 0) {
      console.warn(`No backups found with prefix '${backupPrefix}' in bucket '${bucketName}'.`);
      return res.status(500).send('No recent backups found.');
    }

    const hoursSinceBackup = (Date.now() - latestBackupTimestamp) / 3600000;
    
    // Default to 25 hours, but allow override via environment variable
    const thresholdHours = parseInt(process.env.BACKUP_THRESHOLD_HOURS, 10) || 25;

    if (hoursSinceBackup > thresholdHours) {
      console.error(`Backup is overdue! Last backup was ${hoursSinceBackup.toFixed(2)} hours ago (threshold: ${thresholdHours}h).`);
      // Returning 500 will trigger a GCP Monitoring alert if configured.
      return res.status(500).send('Backup is overdue!');
    } else {
      console.log(`Backups are healthy. Last backup was ${hoursSinceBackup.toFixed(2)} hours ago.`);
      return res.status(200).send('Backups are healthy.');
    }
  } catch (err) {
    console.error('Failed to access backup bucket:', err);
    
    if (err.code === 403) {
      return res.status(500).send('Permission denied accessing backup bucket.');
    } else if (err.code === 404) {
      return res.status(500).send('Backup bucket not found.');
    }
    
    return res.status(500).send(`Backup check failed: ${err.message}`);
  }
};
