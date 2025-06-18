const NotificationService = require('../services/notification-service');
const OutboxService = require('../services/outbox-service');
const MetricsService = require('../services/metrics-service');
const RetryHelper = require('../utils/retry-helper');
const logger = require('../utils/logger');

class StreamProcessor {
  constructor() {
    this.notificationService = new NotificationService();
    this.outboxService = new OutboxService();
    this.metricsService = new MetricsService();
  }

  async handler(event, context) {
    logger.addRequestId(context.awsRequestId);
    
    logger.info('Processing DynamoDB stream records', {
      recordCount: event.Records.length
    });

    const results = {
      processed: 0,
      successful: 0,
      failed: 0,
      errors: []
    };

    for (const record of event.Records) {
      results.processed++;
      
      try {
        await this.processRecord(record);
        results.successful++;
        
        logger.debug('Stream record processed successfully', {
          eventName: record.eventName,
          dynamodb: record.dynamodb ? 'present' : 'missing'
        });
      } catch (error) {
        results.failed++;
        results.errors.push({
          record: {
            eventName: record.eventName,
            dynamodb: record.dynamodb ? 'present' : 'missing'
          },
          error: error.message
        });
        
        logger.error('Error processing stream record', {
          error: error.message,
          stack: error.stack,
          eventName: record.eventName
        });
      }
    }

    logger.info('Stream processing completed', results);

    // Record batch metrics
    await this.metricsService.recordBatch([
      {
        name: 'stream.records.processed',
        value: results.processed,
        dimensions: { source: 'outbox' }
      },
      {
        name: 'stream.records.successful',
        value: results.successful,
        dimensions: { source: 'outbox' }
      },
      {
        name: 'stream.records.failed',
        value: results.failed,
        dimensions: { source: 'outbox' }
      }
    ]);

    return results;
  }

  async processRecord(record) {
    const { eventName, dynamodb } = record;

    // Only process INSERT events from the outbox table
    if (eventName !== 'INSERT' || !dynamodb || !dynamodb.NewImage) {
      logger.debug('Skipping record - not an INSERT with NewImage', {
        eventName,
        hasNewImage: !!(dynamodb && dynamodb.NewImage)
      });
      return;
    }

    // Convert DynamoDB format to regular object
    const outboxEntry = this.convertDynamoDBRecord(dynamodb.NewImage);
    
    logger.info('Processing outbox entry from stream', {
      outboxId: outboxEntry.id,
      notificationId: outboxEntry.notificationId,
      type: outboxEntry.type,
      status: outboxEntry.status
    });

    // Only process pending entries
    if (outboxEntry.status !== 'pending') {
      logger.debug('Skipping outbox entry - not pending', {
        outboxId: outboxEntry.id,
        status: outboxEntry.status
      });
      return;
    }

    // Check if notification is scheduled for future
    if (outboxEntry.scheduledAt && new Date(outboxEntry.scheduledAt) > new Date()) {
      logger.info('Notification scheduled for future, skipping for now', {
        outboxId: outboxEntry.id,
        scheduledAt: outboxEntry.scheduledAt
      });
      return;
    }

    // Process the notification with retry logic
    await RetryHelper.retryWithBackoff(async () => {
      await this.notificationService.processOutboxEntry(outboxEntry);
    }, {
      outboxId: outboxEntry.id,
      type: outboxEntry.type
    });
  }

  convertDynamoDBRecord(dynamoDBImage) {
    const converted = {};
    
    for (const [key, value] of Object.entries(dynamoDBImage)) {
      converted[key] = this.convertDynamoDBValue(value);
    }
    
    return converted;
  }

  convertDynamoDBValue(value) {
    if (value.S) return value.S;
    if (value.N) return Number(value.N);
    if (value.B) return value.B;
    if (value.BOOL) return value.BOOL;
    if (value.NULL) return null;
    if (value.L) return value.L.map(item => this.convertDynamoDBValue(item));
    if (value.M) {
      const obj = {};
      for (const [k, v] of Object.entries(value.M)) {
        obj[k] = this.convertDynamoDBValue(v);
      }
      return obj;
    }
    if (value.SS) return value.SS;
    if (value.NS) return value.NS.map(Number);
    if (value.BS) return value.BS;
    
    // Fallback - return the value as is
    return value;
  }
}

const streamProcessor = new StreamProcessor();
exports.handler = streamProcessor.handler.bind(streamProcessor);