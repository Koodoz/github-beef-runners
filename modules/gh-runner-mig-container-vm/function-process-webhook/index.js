'use strict';

const crypto = require('crypto');
const { http } = require('@google-cloud/functions-framework');
const { MetricServiceClient } = require('@google-cloud/monitoring');
const escapeHtml = require('escape-html');

// ==== ENV variables ====
const GITHUB_WEBHOOK_SECRET = process.env.GITHUB_WEBHOOK_SECRET;
const STACKDRIVER_METRIC_NAME = process.env.STACKDRIVER_METRIC_NAME;
const PROJECT_ID = process.env.PROJECT_ID;

const metricsClient = new MetricServiceClient();

const isValidRequestFromGithub = async (req) => { 
  const signature = crypto
    .createHmac("sha256", GITHUB_WEBHOOK_SECRET)
    .update(JSON.stringify(req.body))
    .digest("hex");
  const expected = Buffer.from(`sha256=${signature}`, 'utf8');
  const actual =  Buffer.from(req.headers.get("x-hub-signature-256"), 'utf8');
  return crypto.timingSafeEqual(expected, actual);
};

const fetchCurrentGaugeValue = async () => {
  // TODO: This is...not an ideal implementation as with enough concurrent
  //       webhook requests, there will be a race condition where the value
  //       could change _after_ this function reads it. This is a known issue
  //       and will be addressed in a future iteration.
  const request = {
    name: `projects/${PROJECT_ID}/metricDescriptors/${STACKDRIVER_METRIC_NAME}`,
  };
  await metricsClient.getMetricDescriptor(request);
  const currentValue = descriptor.metadataValue;
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
    points: [{
      interval: {
        endTime: {
          seconds: Date.now() / 1000,
        },
      },
      value: {
        int64Value: newValue,
      }
    }]
  };
  await metricClient.createTimeSeries(request);
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
  };
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

  const currentValue = await fetchCurrentGaugeValue();
  const newValue = await determineNewGaugeValue(req.body, currentValue);

  if (currentValue !== newValue) {
    setNewGaugeValue(newValue);
  }
  
  return res.status(200);
});
