const crypto = require('crypto');
const { getFunction } = require('@google-cloud/functions-framework/testing');
const { MetricServiceClient } = require('@google-cloud/monitoring');

const GITHUB_WEBHOOK_SECRET = 'test-secret';
const testMetricName = 'test-metric';
const projectId = 'test-project-id';

jest.mock('@google-cloud/monitoring', () => {
  let _currentGaugeValue = 10;

  return {
    ...jest.requireActual('@google-cloud/monitoring'),
    MetricServiceClient: class MockMetricsClient {
      static _setGaugeValue = (newValue) => {
        _currentGaugeValue = newValue;
      };
      static _getGaugeValue = () => _currentGaugeValue;
      getMetricDescriptor = jest
        .fn()
        .mockResolvedValue(
          Promise.resolve({ metadataValue: _currentGaugeValue }),
        );
      createTimeSeries = jest.fn((req) => {
        _currentGaugeValue = req.points[0].value.int64Value;
      });
    },
  };
});

describe('processGithubRunnerWebhook() Cloud Function', () => {
  beforeEach(() => {
    process.env.GITHUB_WEBHOOK_SECRET = GITHUB_WEBHOOK_SECRET;
    process.env.STACKDRIVER_METRIC_NAME = testMetricName;
    process.env.PROJECT_ID = projectId;

    require('./index.js');
  });

  it('should return 401 if request is not from GitHub', async () => {
    const func = getFunction('processGithubRunnerWebhook');
    const res = { status: jest.fn() };

    await func(createStubRequest('invalid-signature', {}), res);
    expect(res.status).toHaveBeenCalledWith(401);
  });

  describe('when the request is from GitHub', () => {
    it('should not do anything if the webhook action is NOT "completed" or "queued"', async () => {
      const webhookPayload = { action: 'in_progress' };

      const func = getFunction('processGithubRunnerWebhook');
      const req = createStubRequest(
        getSignature(webhookPayload),
        webhookPayload,
      );
      const res = { status: jest.fn() };

      await func(req, res);
      expect(res.status).toHaveBeenCalledWith(204);

      // shouldn't have changed from the initial value of 10
      expect(MetricServiceClient._getGaugeValue()).toEqual(10);
    });

    it('should decrement the metric gauge value by 1 if the webhook action is "completed"', async () => {
      const webhookPayload = { action: 'completed' };

      const func = getFunction('processGithubRunnerWebhook');
      const req = createStubRequest(
        getSignature(webhookPayload),
        webhookPayload,
      );
      const res = { status: jest.fn() };

      await func(req, res);
      expect(res.status).toHaveBeenCalledWith(204);

      expect(MetricServiceClient._getGaugeValue()).toEqual(9);
    });

    it('should increment the metric gauge value by 1 if the webhook action is "queued"', async () => {
      const webhookPayload = { action: 'queued' };

      const func = getFunction('processGithubRunnerWebhook');
      const req = createStubRequest(
        getSignature(webhookPayload),
        webhookPayload,
      );
      const res = { status: jest.fn() };

      await func(req, res);
      expect(res.status).toHaveBeenCalledWith(204);

      expect(MetricServiceClient._getGaugeValue()).toEqual(11);
    });
  });
});

const getSignature = (body) =>
  crypto
    .createHmac('sha256', GITHUB_WEBHOOK_SECRET)
    .update(JSON.stringify(body))
    .digest('hex');

const createStubRequest = (signature, payload) => {
  const headers = {
    'x-hub-signature-256': `sha256=${signature}`,
    'Content-Type': 'application/json',
  };
  return {
    headers,
    body: payload,
    get: (headerName) => headers[headerName],
  };
};
