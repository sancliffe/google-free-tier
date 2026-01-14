const { InstancesClient } = require('@google-cloud/compute');
const { Firestore } = require('@google-cloud/firestore');
const compute = new InstancesClient();
const firestore = new Firestore();

async function stopInstanceWithRetry(projectId, zone, instanceName, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      console.log(`Attempt ${i + 1}: Stopping instance ${instanceName} in zone ${zone}...`);
      const [response] = await compute.stop({
        project: projectId,
        zone: zone,
        instance: instanceName,
      });
      
      console.log(`Stop request successful: ${response.status}`);
      return response;
    } catch (err) {
      console.error(`Attempt ${i + 1} failed:`, err.message);
      
      if (i === maxRetries - 1) {
        throw err;
      }
      
      await new Promise(resolve => setTimeout(resolve, 2000 * (i + 1))); // Exponential backoff
    }
  }
}

async function checkOverride() {
    try {
        const doc = await firestore.collection('cost_killer_override').doc('override').get();
        if (doc.exists && doc.data().enabled === true) {
            console.log('Override detected - shutdown will be skipped.');
            return true;
        }
        return false;
    } catch (err) {
        console.error('Error checking for override:', err.message);
        // On error, default to NOT overriding (safe failure)
        return false;
    }
}


/**
 * Triggered from a message on a Cloud Pub/Sub topic.
 *
 * @param {object} message The Pub/Sub message.
 * @param {object} context The event metadata.
 */
exports.stopBilling = async (message, context) => {
  const pubsubData = message.data
    ? JSON.parse(Buffer.from(message.data, 'base64').toString())
    : null;

  if (!pubsubData) {
    console.error('No data received from Pub/Sub.');
    return;
  }

  const costAmount = parseFloat(pubsubData.costAmount) || 0;
  const budgetAmount = parseFloat(pubsubData.budgetAmount) || 0;

  if (isNaN(costAmount) || isNaN(budgetAmount)) {
    console.error(`Invalid amounts - Cost: ${pubsubData.costAmount}, Budget: ${pubsubData.budgetAmount}. Cannot calculate threshold.`);
    return;
  }
  
  if (budgetAmount === 0) {
    console.warn('Budget amount is zero or missing. Cannot calculate threshold.');
    return;
  }

  // Calculate ratio
  const costRatio = costAmount / budgetAmount;
  
  console.log(`Budget Status: $${costAmount} / $${budgetAmount} (Ratio: ${costRatio.toFixed(2)})`);

  // Send a warning when the budget usage is high but below the shutdown threshold
  if (costRatio >= 0.8 && costRatio < 1.0) {
    console.warn('⚠️ Approaching budget limit (80%). VM will shut down at 100%.');
    // TODO: Implement email/Slack notification to alert administrator.
  }

  const shutdownThreshold = parseFloat(process.env.SHUTDOWN_THRESHOLD) || 1.0;

  console.log(`Shutdown threshold is set to: ${shutdownThreshold.toFixed(2)}`);

  // Check if we hit the shutdown threshold
  if (costRatio >= shutdownThreshold) {
    const override = await checkOverride();
    // Allow override only if cost isn't excessively over budget (e.g., 150%)
    if (override && costRatio < 1.5) {
        console.log('Override enabled and cost is within 150% of budget. Skipping shutdown.');
        return;
    }

    console.warn('🚨 Budget limit reached or exceeded! Initiating VM shutdown protocol...');

    const projectId = process.env.PROJECT_ID;
    const zone = process.env.ZONE;
    const instanceName = process.env.INSTANCE_NAME;

    if (instanceName && zone && projectId) {
      try {
        await stopInstanceWithRetry(projectId, zone, instanceName);
      } catch (err) {
        console.error('FATAL ERROR: Failed to stop instance after multiple retries:', err);
      }
    } else {
      console.error('Missing configuration (PROJECT_ID, ZONE, or INSTANCE_NAME). Skipping VM shutdown.');
    }
  } else {
    console.log('Budget is within safe limits.');
  }
};