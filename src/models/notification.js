const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');

// Notification model with validation schemas
class NotificationModel {
  static createSchema = Joi.object({
    type: Joi.string().valid('email', 'sms').required()
      .messages({
        'any.only': 'Type must be either "email" or "sms"',
        'any.required': 'Type is required'
      }),
    recipient: Joi.string().required()
      .when('type', {
        is: 'email',
        then: Joi.string().email().messages({
          'string.email': 'Recipient must be a valid email address for email notifications'
        }),
        otherwise: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).messages({
          'string.pattern.base': 'Recipient must be a valid phone number in E.164 format for SMS notifications'
        })
      }),
    templateId: Joi.string().required()
      .messages({
        'any.required': 'Template ID is required'
      }),
    variables: Joi.object().default({})
      .messages({
        'object.base': 'Variables must be an object'
      }),
    priority: Joi.string().valid('low', 'normal', 'high').default('normal'),
    scheduledAt: Joi.date().iso().optional(),
    metadata: Joi.object().default({})
  });

  static create(data) {
    const { error, value } = this.createSchema.validate(data);
    if (error) {
      throw new Error(`Validation error: ${error.details[0].message}`);
    }

    return {
      id: uuidv4(),
      ...value,
      status: 'pending',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      retryCount: 0,
      maxRetries: 3
    };
  }

  static updateStatus(notification, status, error = null) {
    return {
      ...notification,
      status,
      error,
      updatedAt: new Date().toISOString(),
      ...(status === 'failed' && { retryCount: (notification.retryCount || 0) + 1 })
    };
  }

  static canRetry(notification) {
    return notification.retryCount < notification.maxRetries && 
           notification.status === 'failed';
  }
}

module.exports = NotificationModel;