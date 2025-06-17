const Joi = require('joi');
const { v4: uuidv4 } = require('uuid');

// Template model with validation schemas
class TemplateModel {
  static createSchema = Joi.object({
    name: Joi.string().min(1).max(100).required()
      .messages({
        'any.required': 'Template name is required',
        'string.min': 'Template name must be at least 1 character',
        'string.max': 'Template name must not exceed 100 characters'
      }),
    description: Joi.string().max(500).optional(),
    type: Joi.string().valid('email', 'sms', 'both').default('both')
      .messages({
        'any.only': 'Type must be "email", "sms", or "both"'
      }),
    subject: Joi.string().min(1).max(200).when('type', {
      is: Joi.string().valid('email', 'both'),
      then: Joi.required(),
      otherwise: Joi.optional()
    }).messages({
      'any.required': 'Subject is required for email templates',
      'string.max': 'Subject must not exceed 200 characters'
    }),
    htmlBody: Joi.string().when('type', {
      is: Joi.string().valid('email', 'both'),
      then: Joi.required(),
      otherwise: Joi.optional()
    }).messages({
      'any.required': 'HTML body is required for email templates'
    }),
    textBody: Joi.string().required()
      .messages({
        'any.required': 'Text body is required'
      }),
    variables: Joi.array().items(Joi.string()).default([])
      .messages({
        'array.base': 'Variables must be an array of strings'
      }),
    category: Joi.string().max(50).optional(),
    isActive: Joi.boolean().default(true),
    metadata: Joi.object().default({})
  });

  static updateSchema = Joi.object({
    name: Joi.string().min(1).max(100).optional(),
    description: Joi.string().max(500).optional(),
    type: Joi.string().valid('email', 'sms', 'both').optional(),
    subject: Joi.string().min(1).max(200).optional(),
    htmlBody: Joi.string().optional(),
    textBody: Joi.string().optional(),
    variables: Joi.array().items(Joi.string()).optional(),
    category: Joi.string().max(50).optional(),
    isActive: Joi.boolean().optional(),
    metadata: Joi.object().optional()
  });

  static create(data) {
    const { error, value } = this.createSchema.validate(data);
    if (error) {
      throw new Error(`Validation error: ${error.details[0].message}`);
    }

    // Auto-detect variables in templates
    const detectedVariables = this.extractVariables(value);
    
    return {
      id: uuidv4(),
      ...value,
      variables: [...new Set([...value.variables, ...detectedVariables])], // Merge and dedupe
      version: 1,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
  }

  static update(existingTemplate, updateData) {
    const { error, value } = this.updateSchema.validate(updateData);
    if (error) {
      throw new Error(`Validation error: ${error.details[0].message}`);
    }

    const updated = {
      ...existingTemplate,
      ...value,
      updatedAt: new Date().toISOString(),
      version: existingTemplate.version + 1
    };

    // Re-detect variables if template content changed
    if (value.subject || value.htmlBody || value.textBody) {
      const detectedVariables = this.extractVariables(updated);
      updated.variables = [...new Set([...(value.variables || existingTemplate.variables), ...detectedVariables])];
    }

    return updated;
  }

  static extractVariables(template) {
    const variableRegex = /\{\{(\w+)\}\}/g;
    const variables = new Set();
    
    const texts = [template.subject, template.htmlBody, template.textBody].filter(Boolean);
    
    texts.forEach(text => {
      let match;
      while ((match = variableRegex.exec(text)) !== null) {
        variables.add(match[1]);
      }
    });

    return Array.from(variables);
  }

  static validateVariables(template, providedVariables) {
    const missingVariables = template.variables.filter(
      variable => !(variable in providedVariables)
    );

    if (missingVariables.length > 0) {
      throw new Error(`Missing required variables: ${missingVariables.join(', ')}`);
    }
  }
}

module.exports = TemplateModel;