const { docClient } = require('../utils/aws-clients');
const { PutCommand, GetCommand, UpdateCommand, DeleteCommand, ScanCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const SubscriberModel = require('../models/subscriber');
const logger = require('../utils/logger');

class SubscriberService {
  constructor() {
    this.tableName = process.env.SUBSCRIBERS_TABLE;
  }

  async createSubscriber(subscriberData) {
    try {
      const subscriber = SubscriberModel.create(subscriberData);
      
      const params = {
        TableName: this.tableName,
        Item: subscriber,
        ConditionExpression: 'attribute_not_exists(id)'
      };

      await docClient.send(new PutCommand(params));
      
      logger.info('Subscriber created successfully', { 
        subscriberId: subscriber.id,
        email: subscriber.email,
        phone: subscriber.phone 
      });
      
      return subscriber;
    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        throw new Error('Subscriber already exists');
      }
      logger.error('Error creating subscriber', { error: error.message });
      throw error;
    }
  }

  async getSubscriber(subscriberId) {
    try {
      const params = {
        TableName: this.tableName,
        Key: { id: subscriberId }
      };

      const result = await docClient.send(new GetCommand(params));
      
      if (!result.Item) {
        throw new Error('Subscriber not found');
      }

      return result.Item;
    } catch (error) {
      logger.error('Error getting subscriber', { subscriberId, error: error.message });
      throw error;
    }
  }

  async getSubscriberByEmail(email) {
    try {
      const params = {
        TableName: this.tableName,
        IndexName: 'email-index',
        KeyConditionExpression: 'email = :email',
        ExpressionAttributeValues: {
          ':email': email
        }
      };

      const result = await docClient.send(new QueryCommand(params));
      return result.Items.length > 0 ? result.Items[0] : null;
    } catch (error) {
      logger.error('Error getting subscriber by email', { email, error: error.message });
      throw error;
    }
  }

  async getSubscriberByPhone(phone) {
    try {
      const params = {
        TableName: this.tableName,
        IndexName: 'phone-index',
        KeyConditionExpression: 'phone = :phone',
        ExpressionAttributeValues: {
          ':phone': phone
        }
      };

      const result = await docClient.send(new QueryCommand(params));
      return result.Items.length > 0 ? result.Items[0] : null;
    } catch (error) {
      logger.error('Error getting subscriber by phone', { phone, error: error.message });
      throw error;
    }
  }

  async updateSubscriber(subscriberId, updateData) {
    try {
      // Get existing subscriber first
      const existingSubscriber = await this.getSubscriber(subscriberId);
      const updatedSubscriber = SubscriberModel.update(existingSubscriber, updateData);

      const params = {
        TableName: this.tableName,
        Key: { id: subscriberId },
        UpdateExpression: 'SET #email = :email, #phone = :phone, firstName = :firstName, lastName = :lastName, preferences = :preferences, metadata = :metadata, isActive = :isActive, updatedAt = :updatedAt',
        ExpressionAttributeNames: {
          '#email': 'email',
          '#phone': 'phone'
        },
        ExpressionAttributeValues: {
          ':email': updatedSubscriber.email,
          ':phone': updatedSubscriber.phone,
          ':firstName': updatedSubscriber.firstName,
          ':lastName': updatedSubscriber.lastName,
          ':preferences': updatedSubscriber.preferences,
          ':metadata': updatedSubscriber.metadata,
          ':isActive': updatedSubscriber.isActive,
          ':updatedAt': updatedSubscriber.updatedAt
        },
        ReturnValues: 'ALL_NEW'
      };

      const result = await docClient.send(new UpdateCommand(params));
      
      logger.info('Subscriber updated successfully', { subscriberId });
      return result.Attributes;
    } catch (error) {
      logger.error('Error updating subscriber', { subscriberId, error: error.message });
      throw error;
    }
  }

  async deleteSubscriber(subscriberId) {
    try {
      const params = {
        TableName: this.tableName,
        Key: { id: subscriberId },
        ConditionExpression: 'attribute_exists(id)'
      };

      await docClient.send(new DeleteCommand(params));
      
      logger.info('Subscriber deleted successfully', { subscriberId });
      return { success: true };
    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        throw new Error('Subscriber not found');
      }
      logger.error('Error deleting subscriber', { subscriberId, error: error.message });
      throw error;
    }
  }

  async listSubscribers(limit = 50, lastEvaluatedKey = null) {
    try {
      const params = {
        TableName: this.tableName,
        Limit: limit
      };

      if (lastEvaluatedKey) {
        params.ExclusiveStartKey = lastEvaluatedKey;
      }

      const result = await docClient.send(new ScanCommand(params));
      
      return {
        subscribers: result.Items || [],
        lastEvaluatedKey: result.LastEvaluatedKey
      };
    } catch (error) {
      logger.error('Error listing subscribers', { error: error.message });
      throw error;
    }
  }

  async getActiveSubscribers(notificationType, category = null) {
    try {
      const params = {
        TableName: this.tableName,
        FilterExpression: 'isActive = :isActive',
        ExpressionAttributeValues: {
          ':isActive': true
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      
      // Filter subscribers based on notification preferences
      const filteredSubscribers = (result.Items || []).filter(subscriber => 
        SubscriberModel.canReceiveNotification(subscriber, notificationType, category)
      );

      return filteredSubscribers;
    } catch (error) {
      logger.error('Error getting active subscribers', { 
        notificationType, 
        category, 
        error: error.message 
      });
      throw error;
    }
  }
}

module.exports = SubscriberService;