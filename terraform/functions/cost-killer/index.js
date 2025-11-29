const { InstancesClient } = require('@google-cloud/compute');
const compute = new InstancesClient();

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
    console.error('Invalid cost or budget amount received. Cannot calculate threshold.');
    return;
  }
  
  if (budgetAmount === 0) {
    console.warn('Budget amount is zero or missing. Cannot calculate threshold.');
    return;
  }

  // Calculate ratio
  const costRatio = costAmount / budgetAmount;
  
  console.log(`Budget Status: $${costAmount} / $${budgetAmount} (Ratio: ${costRatio.toFixed(2)})`);

  const shutdownThreshold = parseFloat(process.env.SHUTDOWN_THRESHOLD) || 1.0;

  console.log(`Shutdown threshold is set to: ${shutdownThreshold.toFixed(2)}`);

  // Check if we hit the shutdown threshold
  if (costRatio >= shutdownThreshold) {
    console.warn('🚨 Budget limit reached or exceeded! Initiating VM shutdown protocol...');

    const projectId = process.env.PROJECT_ID;
    const zone = process.env.ZONE;
    const instanceName = process.env.INSTANCE_NAME;

    if (instanceName && zone && projectId) {
      try {
        console.log(`Stopping instance: ${instanceName} in zone ${zone}...`);
        
        const [response] = await compute.stop({
          project: projectId,
          zone: zone,
          instance: instanceName,
        });

        console.log(`Stop request successfully sent. Operation status: ${response.status}`);
      } catch (err) {
        console.error('FATAL ERROR: Failed to stop instance:', err);
      }
    } else {
      console.error('Missing configuration (PROJECT_ID, ZONE, or INSTANCE_NAME). Skipping VM shutdown.');
    }
  } else {
    console.log('Budget is within safe limits.');
  }
};