const { docClient } = require('../utils/aws-clients');
const { ScanCommand, GetCommand, UpdateCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const NotificationService = require('./notification-service');
const MetricsService = require('./metrics-service');
const logger = require('../utils/logger');

class OutboxService {
  constructor() {
    this.outboxTableName = process.env.OUTBOX_TABLE;
    this.metricsService = new MetricsService();
  }

  async processScheduledNotifications() {
    try {
      const now = new Date().toISOString();
      
      const params = {
        TableName: this.outboxTableName,
        FilterExpression: '#status = :pendingStatus AND (attribute_not_exists(scheduledAt) OR scheduledAt <= :now)',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':pendingStatus': 'pending',
          ':now': now
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      const pendingEntries = result.Items || [];

      logger.info('Found pending notifications to process', {
        count: pendingEntries.length
      });

      const processResults = [];
      for (const entry of pendingEntries) {
        try {
          // Create a new instance to avoid circular dependency
          const notificationService = new NotificationService();
          const result = await notificationService.processOutboxEntry(entry);
          
          processResults.push({
            outboxId: entry.id,
            notificationId: entry.notificationId,
            result
          });
        } catch (error) {
          logger.error('Error processing outbox entry', {
            outboxId: entry.id,
            error: error.message
          });
          
          processResults.push({
            outboxId: entry.id,
            notificationId: entry.notificationId,
            error: error.message
          });
        }
      }

      return {
        totalProcessed: pendingEntries.length,
        results: processResults
      };
    } catch (error) {
      logger.error('Error processing scheduled notifications', {
        error: error.message
      });
      throw error;
    }
  }

  async getOutboxEntry(outboxId) {
    try {
      const params = {
        TableName: this.outboxTableName,
        Key: { id: outboxId }
      };

      const result = await docClient.send(new GetCommand(params));
      
      if (!result.Item) {
        throw new Error('Outbox entry not found');
      }

      return result.Item;
    } catch (error) {
      logger.error('Error getting outbox entry', {
        outboxId,
        error: error.message
      });
      throw error;
    }
  }

  async updateOutboxEntryStatus(outboxId, status, error = null) {
    try {
      const updateParams = {
        TableName: this.outboxTableName,
        Key: { id: outboxId },
        UpdateExpression: 'SET #status = :status, updatedAt = :updatedAt',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':status': status,
          ':updatedAt': new Date().toISOString()
        }
      };

      if (error) {
        updateParams.UpdateExpression += ', #error = :error, retryCount = retryCount + :increment';
        updateParams.ExpressionAttributeNames['#error'] = 'error';
        updateParams.ExpressionAttributeValues[':error'] = error;
        updateParams.ExpressionAttributeValues[':increment'] = 1;
      }

      await docClient.send(new UpdateCommand(updateParams));
      
      logger.debug('Outbox entry status updated', {
        outboxId,
        status,
        hasError: !!error
      });
    } catch (updateError) {
      logger.error('Error updating outbox entry status', {
        outboxId,
        error: updateError.message
      });
      throw updateError;
    }
  }

  async getOutboxStats() {
    try {
      const params = {
        TableName: this.outboxTableName
      };

      const result = await docClient.send(new ScanCommand(params));
      const entries = result.Items || [];

      const stats = {
        total: entries.length,
        pending: 0,
        sent: 0,
        failed: 0,
        scheduled: 0
      };

      const now = new Date();
      
      entries.forEach(entry => {
        stats[entry.status] = (stats[entry.status] || 0) + 1;
        
        if (entry.scheduledAt && new Date(entry.scheduledAt) > now) {
          stats.scheduled++;
        }
      });

      return stats;
    } catch (error) {
      logger.error('Error getting outbox stats', {
        error: error.message
      });
      throw error;
    }
  }

  async cleanupOldEntries(daysOld = 7) {
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);
      const cutoffTimestamp = cutoffDate.toISOString();

      const params = {
        TableName: this.outboxTableName,
        FilterExpression: 'createdAt < :cutoff AND (#status = :sentStatus OR #status = :failedStatus)',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':cutoff': cutoffTimestamp,
          ':sentStatus': 'sent',
          ':failedStatus': 'failed'
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      const oldEntries = result.Items || [];

      logger.info('Found old outbox entries for cleanup', {
        count: oldEntries.length,
        cutoffDate: cutoffTimestamp
      });

      let deletedCount = 0;
      for (const entry of oldEntries) {
        try {
          const deleteParams = {
            TableName: this.outboxTableName,
            Key: { id: entry.id }
          };

          await docClient.send(new DeleteCommand(deleteParams));
          deletedCount++;
        } catch (error) {
          logger.error('Error deleting old outbox entry', {
            outboxId: entry.id,
            error: error.message
          });
        }
      }

      logger.info('Outbox cleanup completed', {
        totalFound: oldEntries.length,
        deleted: deletedCount
      });

      return {
        totalFound: oldEntries.length,
        deleted: deletedCount
      };
    } catch (error) {
      logger.error('Error cleaning up old outbox entries', {
        error: error.message
      });
      throw error;
    }
  }

  async getFailedNotifications(limit = 50) {
    try {
      const params = {
        TableName: this.outboxTableName,
        FilterExpression: '#status = :failedStatus',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':failedStatus': 'failed'
        },
        Limit: limit
      };

      const result = await docClient.send(new ScanCommand(params));
      
      return result.Items || [];
    } catch (error) {
      logger.error('Error getting failed notifications', {
        error: error.message
      });
      throw error;
    }
  }

  async requeueFailedNotification(outboxId) {
    try {
      const entry = await this.getOutboxEntry(outboxId);
      
      if (entry.status !== 'failed') {
        throw new Error('Only failed notifications can be requeued');
      }

      if (entry.retryCount >= entry.maxRetries) {
        throw new Error('Maximum retry attempts exceeded');
      }

      await this.updateOutboxEntryStatus(outboxId, 'pending');
      
      logger.info('Notification requeued successfully', {
        outboxId,
        retryCount: entry.retryCount
      });

      return { success: true, retryCount: entry.retryCount };
    } catch (error) {
      logger.error('Error requeuing failed notification', {
        outboxId,
        error: error.message
      });
      throw error;
    }
  }
}

module.exports = OutboxService;