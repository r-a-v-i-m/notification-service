const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');

// Subscriber model with validation schemas
class SubscriberModel {
  static createSchema = Joi.object({
    email: Joi.string().email().optional()
      .messages({
        'string.email': 'Email must be a valid email address'
      }),
    phone: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).optional()
      .messages({
        'string.pattern.base': 'Phone must be a valid phone number in E.164 format'
      }),
    firstName: Joi.string().min(1).max(100).optional(),
    lastName: Joi.string().min(1).max(100).optional(),
    preferences: Joi.object({
      email: Joi.boolean().default(true),
      sms: Joi.boolean().default(true),
      categories: Joi.array().items(Joi.string()).default([])
    }).default(),
    metadata: Joi.object().default({}),
    isActive: Joi.boolean().default(true)
  }).or('email', 'phone').messages({
    'object.missing': 'Either email or phone number is required'
  });

  static updateSchema = Joi.object({
    email: Joi.string().email().optional(),
    phone: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).optional(),
    firstName: Joi.string().min(1).max(100).optional(),
    lastName: Joi.string().min(1).max(100).optional(),
    preferences: Joi.object({
      email: Joi.boolean(),
      sms: Joi.boolean(),
      categories: Joi.array().items(Joi.string())
    }).optional(),
    metadata: Joi.object().optional(),
    isActive: Joi.boolean().optional()
  });

  static create(data) {
    const { error, value } = this.createSchema.validate(data);
    if (error) {
      throw new Error(`Validation error: ${error.details[0].message}`);
    }

    return {
      id: uuidv4(),
      ...value,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
  }

  static update(existingSubscriber, updateData) {
    const { error, value } = this.updateSchema.validate(updateData);
    if (error) {
      throw new Error(`Validation error: ${error.details[0].message}`);
    }

    return {
      ...existingSubscriber,
      ...value,
      updatedAt: new Date().toISOString()
    };
  }

  static canReceiveNotification(subscriber, notificationType, category = null) {
    if (!subscriber.isActive) {
      return false;
    }

    const preferences = subscriber.preferences || {};
    
    // Check notification type preference
    if (notificationType === 'email' && !preferences.email) {
      return false;
    }
    if (notificationType === 'sms' && !preferences.sms) {
      return false;
    }

    // Check category preference if specified
    if (category && preferences.categories && preferences.categories.length > 0) {
      return preferences.categories.includes(category);
    }

    return true;
  }
}

module.exports = SubscriberModel;