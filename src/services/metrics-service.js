const { cloudwatchClient } = require('../utils/aws-clients');
const { PutMetricDataCommand } = require('@aws-sdk/client-cloudwatch');
const logger = require('../utils/logger');

class MetricsService {
  constructor() {
    this.namespace = 'NotificationService';
    this.environment = process.env.ENVIRONMENT || 'dev';
  }

  async incrementCounter(metricName, dimensions = {}, value = 1) {
    try {
      const metricData = {
        MetricName: metricName,
        Value: value,
        Unit: 'Count',
        Timestamp: new Date(),
        Dimensions: [
          {
            Name: 'Environment',
            Value: this.environment
          },
          ...Object.entries(dimensions).map(([key, value]) => ({
            Name: key,
            Value: String(value)
          }))
        ]
      };

      const params = {
        Namespace: this.namespace,
        MetricData: [metricData]
      };

      await cloudwatchClient.send(new PutMetricDataCommand(params));
      
      logger.debug('Metric published successfully', {
        metricName,
        value,
        dimensions
      });
    } catch (error) {
      logger.error('Error publishing metric', {
        metricName,
        error: error.message
      });
      // Don't throw error to avoid breaking the main flow
    }
  }

  async recordDuration(metricName, durationMs, dimensions = {}) {
    try {
      const metricData = {
        MetricName: metricName,
        Value: durationMs,
        Unit: 'Milliseconds',
        Timestamp: new Date(),
        Dimensions: [
          {
            Name: 'Environment',
            Value: this.environment
          },
          ...Object.entries(dimensions).map(([key, value]) => ({
            Name: key,
            Value: String(value)
          }))
        ]
      };

      const params = {
        Namespace: this.namespace,
        MetricData: [metricData]
      };

      await cloudwatchClient.send(new PutMetricDataCommand(params));
      
      logger.debug('Duration metric published successfully', {
        metricName,
        durationMs,
        dimensions
      });
    } catch (error) {
      logger.error('Error publishing duration metric', {
        metricName,
        error: error.message
      });
    }
  }

  async recordValue(metricName, value, unit = 'Count', dimensions = {}) {
    try {
      const metricData = {
        MetricName: metricName,
        Value: value,
        Unit: unit,
        Timestamp: new Date(),
        Dimensions: [
          {
            Name: 'Environment',
            Value: this.environment
          },
          ...Object.entries(dimensions).map(([key, value]) => ({
            Name: key,
            Value: String(value)
          }))
        ]
      };

      const params = {
        Namespace: this.namespace,
        MetricData: [metricData]
      };

      await cloudwatchClient.send(new PutMetricDataCommand(params));
      
      logger.debug('Value metric published successfully', {
        metricName,
        value,
        unit,
        dimensions
      });
    } catch (error) {
      logger.error('Error publishing value metric', {
        metricName,
        error: error.message
      });
    }
  }

  async recordBatch(metrics) {
    try {
      const metricData = metrics.map(metric => ({
        MetricName: metric.name,
        Value: metric.value,
        Unit: metric.unit || 'Count',
        Timestamp: new Date(),
        Dimensions: [
          {
            Name: 'Environment',
            Value: this.environment
          },
          ...Object.entries(metric.dimensions || {}).map(([key, value]) => ({
            Name: key,
            Value: String(value)
          }))
        ]
      }));

      const params = {
        Namespace: this.namespace,
        MetricData: metricData
      };

      await cloudwatchClient.send(new PutMetricDataCommand(params));
      
      logger.debug('Batch metrics published successfully', {
        count: metrics.length
      });
    } catch (error) {
      logger.error('Error publishing batch metrics', {
        error: error.message
      });
    }
  }

  // Convenience methods for common metrics
  async recordNotificationSent(type, templateId, priority = 'normal') {
    await this.incrementCounter('notifications.sent', {
      type,
      templateId,
      priority
    });
  }

  async recordNotificationFailed(type, templateId, errorType, priority = 'normal') {
    await this.incrementCounter('notifications.failed', {
      type,
      templateId,
      errorType,
      priority
    });
  }

  async recordApiRequest(endpoint, method, statusCode, durationMs) {
    const metrics = [
      {
        name: 'api.requests',
        value: 1,
        unit: 'Count',
        dimensions: { endpoint, method, statusCode: String(statusCode) }
      },
      {
        name: 'api.response_time',
        value: durationMs,
        unit: 'Milliseconds',
        dimensions: { endpoint, method }
      }
    ];

    await this.recordBatch(metrics);
  }

  async recordTemplateUsage(templateId, templateName, type) {
    await this.incrementCounter('templates.used', {
      templateId,
      templateName,
      type
    });
  }

  async recordOutboxProcessing(status, type, priority = 'normal') {
    await this.incrementCounter('outbox.processed', {
      status,
      type,
      priority
    });
  }
}

module.exports = MetricsService;