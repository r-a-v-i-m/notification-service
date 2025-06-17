const NotificationService = require('../services/notification-service');
const OutboxService = require('../services/outbox-service');
const MetricsService = require('../services/metrics-service');
const RetryHelper = require('../utils/retry-helper');
const logger = require('../utils/logger');

class DLQProcessor {
  constructor() {
    this.notificationService = new NotificationService();
    this.outboxService = new OutboxService();
    this.metricsService = new MetricsService();
  }

  async handler(event, context) {
    logger.addRequestId(context.awsRequestId);
    
    logger.info('Processing DLQ messages', {
      messageCount: event.Records.length
    });

    const results = {
      processed: 0,
      successful: 0,
      failed: 0,
      permanentlyFailed: 0,
      errors: []
    };

    for (const record of event.Records) {
      results.processed++;
      
      try {
        const result = await this.processMessage(record);
        
        if (result.status === 'success') {
          results.successful++;
        } else if (result.status === 'permanently_failed') {
          results.permanentlyFailed++;
        } else {
          results.failed++;
        }
        
        logger.debug('DLQ message processed', {
          messageId: record.messageId,
          status: result.status
        });
      } catch (error) {
        results.failed++;
        results.errors.push({
          messageId: record.messageId,
          error: error.message
        });
        
        logger.error('Error processing DLQ message', {
          messageId: record.messageId,
          error: error.message,
          stack: error.stack
        });
      }
    }

    logger.info('DLQ processing completed', results);

    // Record metrics
    await this.metricsService.recordBatch([
      {
        name: 'dlq.messages.processed',
        value: results.processed
      },
      {
        name: 'dlq.messages.successful',
        value: results.successful
      },
      {
        name: 'dlq.messages.failed',
        value: results.failed
      },
      {
        name: 'dlq.messages.permanently_failed',
        value: results.permanentlyFailed
      }
    ]);

    return results;
  }

  async processMessage(record) {
    try {
      const message = JSON.parse(record.body);
      
      logger.info('Processing DLQ message', {
        messageId: record.messageId,
        messageType: typeof message,
        hasOriginalRecord: !!message.record
      });

      // Handle different message formats
      let outboxEntry;
      if (message.record && message.record.dynamodb && message.record.dynamodb.NewImage) {
        // Message from stream processor failure
        outboxEntry = this.convertDynamoDBRecord(message.record.dynamodb.NewImage);
      } else if (message.outboxId) {
        // Direct outbox reference
        outboxEntry = await this.outboxService.getOutboxEntry(message.outboxId);
      } else if (message.id) {
        // Outbox entry directly in message
        outboxEntry = message;
      } else {
        throw new Error('Unable to extract outbox entry from DLQ message');
      }

      logger.info('Extracted outbox entry from DLQ message', {
        outboxId: outboxEntry.id,
        notificationId: outboxEntry.notificationId,
        type: outboxEntry.type,
        status: outboxEntry.status,
        retryCount: outboxEntry.retryCount
      });

      // Check if we've exceeded max retries
      if (outboxEntry.retryCount >= (outboxEntry.maxRetries || 3)) {
        logger.warn('Notification exceeded max retries, marking as permanently failed', {
          outboxId: outboxEntry.id,
          retryCount: outboxEntry.retryCount,
          maxRetries: outboxEntry.maxRetries
        });

        await this.markAsPermanentlyFailed(outboxEntry);
        return { status: 'permanently_failed' };
      }

      // Attempt to process the notification again
      await this.retryNotification(outboxEntry);
      
      logger.info('DLQ notification processed successfully', {
        outboxId: outboxEntry.id,
        retryCount: outboxEntry.retryCount
      });

      return { status: 'success' };
      
    } catch (error) {
      logger.error('Error processing DLQ message', {
        messageId: record.messageId,
        error: error.message,
        stack: error.stack
      });

      // Check if this is a retryable error
      if (RetryHelper.isRetryableError(error)) {
        return { status: 'failed', retryable: true };
      } else {
        return { status: 'failed', retryable: false };
      }
    }
  }

  async retryNotification(outboxEntry) {
    try {
      // Use exponential backoff for the retry
      await RetryHelper.exponentialBackoff(
        async () => {
          await this.notificationService.processOutboxEntry(outboxEntry);
        },
        2, // Max 2 additional retries in DLQ processor
        2000, // 2 second base delay
        10000, // 10 second max delay
        2, // Exponential factor
        true // Add jitter
      );

      logger.info('DLQ notification retry successful', {
        outboxId: outboxEntry.id
      });

    } catch (error) {
      logger.error('DLQ notification retry failed', {
        outboxId: outboxEntry.id,
        error: error.message
      });

      // Update the outbox entry with the failure
      await this.outboxService.updateOutboxEntryStatus(
        outboxEntry.id, 
        'failed', 
        `DLQ retry failed: ${error.message}`
      );

      throw error;
    }
  }

  async markAsPermanentlyFailed(outboxEntry) {
    try {
      await this.outboxService.updateOutboxEntryStatus(
        outboxEntry.id, 
        'permanently_failed', 
        'Exceeded maximum retry attempts'
      );

      // Record permanent failure metric
      await this.metricsService.incrementCounter('notifications.permanently_failed', {
        type: outboxEntry.type,
        priority: outboxEntry.priority || 'normal'
      });

      logger.error('Notification marked as permanently failed', {
        outboxId: outboxEntry.id,
        notificationId: outboxEntry.notificationId,
        type: outboxEntry.type,
        retryCount: outboxEntry.retryCount
      });

    } catch (error) {
      logger.error('Error marking notification as permanently failed', {
        outboxId: outboxEntry.id,
        error: error.message
      });
      throw error;
    }
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
    
    return value;
  }
}

const dlqProcessor = new DLQProcessor();
exports.handler = dlqProcessor.handler.bind(dlqProcessor);