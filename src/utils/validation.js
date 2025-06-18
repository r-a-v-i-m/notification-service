const Joi = require('joi');

class ValidationHelper {
  static validateEmail(email) {
    const schema = Joi.string().email().required();
    const { error } = schema.validate(email);
    return !error;
  }

  static validatePhoneNumber(phone) {
    const schema = Joi.string().pattern(/^\+[1-9]\d{1,14}$/).required();
    const { error } = schema.validate(phone);
    return !error;
  }

  static validateUUID(uuid) {
    const schema = Joi.string().uuid().required();
    const { error } = schema.validate(uuid);
    return !error;
  }

  static validateNotificationRequest(req) {
    const schema = Joi.object({
      type: Joi.string().valid('email', 'sms').required(),
      recipient: Joi.string().required(),
      templateId: Joi.string().uuid().required(),
      variables: Joi.object().default({}),
      priority: Joi.string().valid('low', 'normal', 'high').default('normal'),
      scheduledAt: Joi.date().iso().optional()
    });

    return schema.validate(req);
  }

  static validateBulkNotificationRequest(req) {
    const schema = Joi.object({
      notifications: Joi.array().items(
        Joi.object({
          type: Joi.string().valid('email', 'sms').required(),
          recipient: Joi.string().required(),
          templateId: Joi.string().uuid().required(),
          variables: Joi.object().default({}),
          priority: Joi.string().valid('low', 'normal', 'high').default('normal'),
          scheduledAt: Joi.date().iso().optional()
        })
      ).min(1).max(100).required()
    });

    return schema.validate(req);
  }

  static validateSubscriberRequest(req) {
    const schema = Joi.object({
      email: Joi.string().email().optional(),
      phone: Joi.string().pattern(/^\+[1-9]\d{1,14}$/).optional(),
      firstName: Joi.string().min(1).max(100).optional(),
      lastName: Joi.string().min(1).max(100).optional(),
      preferences: Joi.object({
        email: Joi.boolean().default(true),
        sms: Joi.boolean().default(true),
        categories: Joi.array().items(Joi.string()).default([])
      }).default(),
      metadata: Joi.object().default({})
    }).or('email', 'phone');

    return schema.validate(req);
  }

  static validateTemplateRequest(req) {
    const schema = Joi.object({
      name: Joi.string().min(1).max(100).required(),
      description: Joi.string().max(500).optional(),
      type: Joi.string().valid('email', 'sms', 'both').default('both'),
      subject: Joi.string().min(1).max(200).when('type', {
        is: Joi.string().valid('email', 'both'),
        then: Joi.required(),
        otherwise: Joi.optional()
      }),
      htmlBody: Joi.string().when('type', {
        is: Joi.string().valid('email', 'both'),
        then: Joi.required(),
        otherwise: Joi.optional()
      }),
      textBody: Joi.string().required(),
      variables: Joi.array().items(Joi.string()).default([]),
      category: Joi.string().max(50).optional(),
      metadata: Joi.object().default({})
    });

    return schema.validate(req);
  }

  static validatePaginationParams(req) {
    const schema = Joi.object({
      limit: Joi.number().integer().min(1).max(100).default(50),
      lastKey: Joi.string().optional()
    });

    return schema.validate(req);
  }

  static sanitizeInput(input) {
    if (typeof input === 'string') {
      return input.trim();
    }
    return input;
  }

  static sanitizeObject(obj) {
    const sanitized = {};
    for (const [key, value] of Object.entries(obj)) {
      sanitized[key] = this.sanitizeInput(value);
    }
    return sanitized;
  }

  static createErrorResponse(error, statusCode = 400) {
    if (error.isJoi) {
      return {
        statusCode,
        error: 'Validation Error',
        message: error.details[0].message,
        details: error.details
      };
    }

    return {
      statusCode: statusCode >= 400 ? statusCode : 500,
      error: error.name || 'Error',
      message: error.message || 'An error occurred'
    };
  }
}

module.exports = ValidationHelper;