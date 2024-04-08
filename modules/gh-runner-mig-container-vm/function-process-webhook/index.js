'use strict';

const crypto = require('crypto');
const { http } = require('@google-cloud/functions-framework');
const { MetricServiceClient } = require('@google-cloud/monitoring');

// ==== ENV variables ====
const GITHUB_WEBHOOK_SECRET = process.env.GITHUB_WEBHOOK_SECRET;
const STACKDRIVER_METRIC_NAME = process.env.STACKDRIVER_METRIC_NAME;
const PROJECT_ID = process.env.PROJECT_ID;

const metricsClient = new MetricServiceClient();

const isValidRequestFromGithub = async (req) => {
  const expectedSignature = crypto
    .createHmac('sha256', GITHUB_WEBHOOK_SECRET)
    .update(JSON.stringify(req.body))
    .digest('hex');
  const actualSignature = req.get('x-hub-signature-256');

  if (!actualSignature) {
    console.log('No signature specified', actualSignature);
    return false;
  }
  const expected = Buffer.from(`sha256=${expectedSignature}`, 'utf8');
  const actual = Buffer.from(actualSignature, 'utf8');

  try {
    return crypto.timingSafeEqual(expected, actual);
  } catch (RangeError) {
    return false;
  }
};

const fetchCurrentGaugeValue = async () => {
  const request = {
    name: `projects/${PROJECT_ID}/metricDescriptors/${STACKDRIVER_METRIC_NAME}`,
  };

  const descriptor = await metricsClient.getMetricDescriptor(request);
  return descriptor.metadataValue;
};

const setNewGaugeValue = async (newValue) => {
  const request = {
    metric: {
      metricType: STACKDRIVER_METRIC_NAME,
    },
    resource: {
      type: 'global',
      labels: {
        project_id: PROJECT_ID,
      },
    },
    points: [
      {
        interval: {
          endTime: {
            seconds: Date.now() / 1000,
          },
        },
        value: {
          int64Value: newValue,
        },
      },
    ],
  };
  await metricsClient.createTimeSeries(request);
};

const determineNewGaugeValue = async (webhookPayload, currentValue) => {
  // NOTE: we ignore 'in_progress' webhooks as they are already being run
  //      and we only care about the 'queued' and 'completed' states so that
  //      we scale down or scale up the instances accordingly
  switch (webhookPayload.action) {
    case 'completed':
      return currentValue - 1;
    case 'queued':
      return currentValue + 1;
    default:
      return currentValue;
  }
};

/**
 *
 * @param {Object} req Cloud Function request context.
 * @param {Object} res Cloud Function response context.
 */
http('processGithubRunnerWebhook', async (req, res) => {
  const isValid = await isValidRequestFromGithub(req);

  if (!isValid) {
    return res.status(401);
  }

  // TODO: This is...not an ideal implementation as with enough concurrent
  //       webhook requests, there will be a race condition where the value
  //       could change _after_ this function reads it. This is a known issue
  //       and will be addressed in a future iteration.
  const currentValue = await fetchCurrentGaugeValue();
  const newValue = await determineNewGaugeValue(req.body, currentValue);

  if (currentValue !== newValue) {
    setNewGaugeValue(newValue);
  }

  return res.status(204);
});
