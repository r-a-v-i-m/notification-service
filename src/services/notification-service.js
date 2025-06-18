const { v4: uuidv4 } = require('uuid');
const { docClient, sesClient, snsClient } = require('../utils/aws-clients');
const { PutCommand, GetCommand, UpdateCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { SendEmailCommand } = require('@aws-sdk/client-ses');
const { PublishCommand } = require('@aws-sdk/client-sns');
const NotificationModel = require('../models/notification');
const TemplateService = require('./template-service');
const SubscriberService = require('./subscriber-service');
const MetricsService = require('./metrics-service');
const logger = require('../utils/logger');

class NotificationService {
  constructor() {
    this.templateService = new TemplateService();
    this.subscriberService = new SubscriberService();
    this.metricsService = new MetricsService();
    this.outboxTableName = process.env.OUTBOX_TABLE;
    this.fromEmail = process.env.SES_FROM_EMAIL;
  }

  async sendNotification({ type, recipient, templateId, variables = {}, priority = 'normal', scheduledAt = null }) {
    try {
      const notification = NotificationModel.create({
        type,
        recipient,
        templateId,
        variables,
        priority,
        scheduledAt
      });

      logger.info('Creating notification', {
        notificationId: notification.id,
        type,
        recipient: this.maskSensitiveData(recipient),
        templateId,
        priority
      });

      // Get and validate template
      const template = await this.templateService.getTemplate(templateId);
      if (!template) {
        throw new Error(`Template ${templateId} not found`);
      }

      // Validate template type compatibility
      if (template.type !== 'both' && template.type !== type) {
        throw new Error(`Template ${templateId} is not compatible with notification type ${type}`);
      }

      // Render template with variables
      const renderedContent = this.templateService.renderTemplate(template, variables);

      // Store in outbox for transactional guarantee (outbox pattern)
      const outboxEntry = await this.storeInOutbox(notification, renderedContent);

      // Record metrics
      await this.metricsService.incrementCounter('notifications.created', {
        type,
        priority,
        templateId
      });

      logger.info('Notification queued successfully', {
        notificationId: notification.id,
        outboxId: outboxEntry.id
      });

      return {
        notificationId: notification.id,
        status: 'queued',
        scheduledAt: notification.scheduledAt
      };
    } catch (error) {
      logger.error('Error creating notification', {
        error: error.message,
        stack: error.stack,
        type,
        templateId
      });
      
      await this.metricsService.incrementCounter('notifications.creation_failed', {
        type,
        templateId,
        errorType: error.constructor.name
      });
      
      throw error;
    }
  }

  async sendBulkNotifications(notifications) {
    const results = [];
    const errors = [];

    for (const notificationData of notifications) {
      try {
        const result = await this.sendNotification(notificationData);
        results.push(result);
      } catch (error) {
        errors.push({
          notification: notificationData,
          error: error.message
        });
      }
    }

    logger.info('Bulk notification processing completed', {
      total: notifications.length,
      successful: results.length,
      failed: errors.length
    });

    return {
      successful: results,
      failed: errors,
      summary: {
        total: notifications.length,
        successful: results.length,
        failed: errors.length
      }
    };
  }

  async storeInOutbox(notification, renderedContent) {
    const ttl = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days TTL
    
    const outboxEntry = {
      id: uuidv4(),
      notificationId: notification.id,
      type: notification.type,
      recipient: notification.recipient,
      content: renderedContent,
      priority: notification.priority,
      scheduledAt: notification.scheduledAt,
      status: 'pending',
      retryCount: 0,
      maxRetries: 3,
      ttl,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: this.outboxTableName,
      Item: outboxEntry
    };

    await docClient.send(new PutCommand(params));
    
    logger.debug('Outbox entry created', {
      outboxId: outboxEntry.id,
      notificationId: notification.id
    });

    return outboxEntry;
  }

  async processOutboxEntry(outboxEntry) {
    try {
      logger.info('Processing outbox entry', {
        outboxId: outboxEntry.id,
        type: outboxEntry.type,
        recipient: this.maskSensitiveData(outboxEntry.recipient)
      });

      // Check if notification is scheduled for future
      if (outboxEntry.scheduledAt && new Date(outboxEntry.scheduledAt) > new Date()) {
        logger.info('Notification scheduled for future, skipping', {
          outboxId: outboxEntry.id,
          scheduledAt: outboxEntry.scheduledAt
        });
        return { status: 'scheduled' };
      }

      let result;
      if (outboxEntry.type === 'email') {
        result = await this.sendEmail(outboxEntry.recipient, outboxEntry.content);
      } else if (outboxEntry.type === 'sms') {
        result = await this.sendSMS(outboxEntry.recipient, outboxEntry.content);
      } else {
        throw new Error(`Unsupported notification type: ${outboxEntry.type}`);
      }

      // Update outbox entry status
      await this.updateOutboxEntryStatus(outboxEntry.id, 'sent', null, result);

      // Record success metrics
      await this.metricsService.incrementCounter('notifications.sent', {
        type: outboxEntry.type,
        priority: outboxEntry.priority
      });

      logger.info('Notification sent successfully', {
        outboxId: outboxEntry.id,
        messageId: result.messageId,
        type: outboxEntry.type
      });

      return { status: 'sent', messageId: result.messageId };
    } catch (error) {
      logger.error('Error processing outbox entry', {
        outboxId: outboxEntry.id,
        error: error.message,
        stack: error.stack
      });

      // Update outbox entry with error
      await this.updateOutboxEntryStatus(outboxEntry.id, 'failed', error.message);

      // Record failure metrics
      await this.metricsService.incrementCounter('notifications.failed', {
        type: outboxEntry.type,
        priority: outboxEntry.priority,
        errorType: error.constructor.name
      });

      throw error;
    }
  }

  async sendEmail(recipient, content) {
    try {
      const params = {
        Source: this.fromEmail,
        Destination: {
          ToAddresses: [recipient]
        },
        Message: {
          Subject: {
            Data: content.subject,
            Charset: 'UTF-8'
          },
          Body: {
            ...(content.html && {
              Html: {
                Data: content.html,
                Charset: 'UTF-8'
              }
            }),
            Text: {
              Data: content.text,
              Charset: 'UTF-8'
            }
          }
        }
      };

      const result = await sesClient.send(new SendEmailCommand(params));
      
      logger.debug('Email sent via SES', {
        messageId: result.MessageId,
        recipient: this.maskSensitiveData(recipient)
      });

      return {
        messageId: result.MessageId,
        status: 'sent',
        provider: 'SES'
      };
    } catch (error) {
      logger.error('Error sending email', {
        error: error.message,
        recipient: this.maskSensitiveData(recipient),
        fromEmail: this.fromEmail
      });
      throw error;
    }
  }

  async sendSMS(recipient, content) {
    try {
      const params = {
        PhoneNumber: recipient,
        Message: content.text,
        MessageAttributes: {
          'AWS.SNS.SMS.SMSType': {
            DataType: 'String',
            StringValue: 'Transactional'
          }
        }
      };

      const result = await snsClient.send(new PublishCommand(params));
      
      logger.debug('SMS sent via SNS', {
        messageId: result.MessageId,
        recipient: this.maskSensitiveData(recipient)
      });

      return {
        messageId: result.MessageId,
        status: 'sent',
        provider: 'SNS'
      };
    } catch (error) {
      logger.error('Error sending SMS', {
        error: error.message,
        recipient: this.maskSensitiveData(recipient)
      });
      throw error;
    }
  }

  async updateOutboxEntryStatus(outboxId, status, error = null, result = null) {
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

      if (result) {
        updateParams.UpdateExpression += ', result = :result';
        updateParams.ExpressionAttributeValues[':result'] = result;
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

  async getNotificationStatus(notificationId) {
    try {
      const params = {
        TableName: this.outboxTableName,
        FilterExpression: 'notificationId = :notificationId',
        ExpressionAttributeValues: {
          ':notificationId': notificationId
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      
      if (result.Items.length === 0) {
        throw new Error('Notification not found');
      }

      const outboxEntry = result.Items[0];
      
      return {
        notificationId,
        status: outboxEntry.status,
        type: outboxEntry.type,
        recipient: this.maskSensitiveData(outboxEntry.recipient),
        createdAt: outboxEntry.createdAt,
        updatedAt: outboxEntry.updatedAt,
        retryCount: outboxEntry.retryCount,
        error: outboxEntry.error,
        result: outboxEntry.result
      };
    } catch (error) {
      logger.error('Error getting notification status', {
        notificationId,
        error: error.message
      });
      throw error;
    }
  }

  async retryFailedNotifications(maxRetries = 3) {
    try {
      const params = {
        TableName: this.outboxTableName,
        FilterExpression: '#status = :failedStatus AND retryCount < :maxRetries',
        ExpressionAttributeNames: {
          '#status': 'status'
        },
        ExpressionAttributeValues: {
          ':failedStatus': 'failed',
          ':maxRetries': maxRetries
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      const failedEntries = result.Items || [];

      logger.info('Found failed notifications for retry', {
        count: failedEntries.length
      });

      const retryResults = [];
      for (const entry of failedEntries) {
        try {
          // Reset status to pending for retry
          await this.updateOutboxEntryStatus(entry.id, 'pending');
          
          // Process the entry
          const result = await this.processOutboxEntry(entry);
          retryResults.push({
            outboxId: entry.id,
            notificationId: entry.notificationId,
            result
          });
        } catch (error) {
          logger.error('Error retrying notification', {
            outboxId: entry.id,
            error: error.message
          });
        }
      }

      return {
        totalRetried: failedEntries.length,
        results: retryResults
      };
    } catch (error) {
      logger.error('Error retrying failed notifications', {
        error: error.message
      });
      throw error;
    }
  }

  maskSensitiveData(data) {
    if (!data) return data;
    
    if (data.includes('@')) {
      // Email masking
      const [localPart, domain] = data.split('@');
      return `${localPart.substring(0, 2)}***@${domain}`;
    } else if (data.startsWith('+')) {
      // Phone number masking
      return `${data.substring(0, 3)}***${data.substring(data.length - 2)}`;
    }
    
    return data;
  }
}

module.exports = NotificationService;