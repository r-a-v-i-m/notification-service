const Handlebars = require('handlebars');
const { docClient } = require('../utils/aws-clients');
const { PutCommand, GetCommand, UpdateCommand, DeleteCommand, ScanCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const TemplateModel = require('../models/template');
const logger = require('../utils/logger');

class TemplateService {
  constructor() {
    this.tableName = process.env.TEMPLATES_TABLE;
    this.compiledTemplates = new Map(); // Cache for compiled templates
  }

  async createTemplate(templateData) {
    try {
      const template = TemplateModel.create(templateData);
      
      const params = {
        TableName: this.tableName,
        Item: template,
        ConditionExpression: 'attribute_not_exists(id)'
      };

      await docClient.send(new PutCommand(params));
      
      logger.info('Template created successfully', { 
        templateId: template.id,
        name: template.name,
        type: template.type 
      });
      
      return template;
    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        throw new Error('Template with this ID already exists');
      }
      logger.error('Error creating template', { error: error.message });
      throw error;
    }
  }

  async getTemplate(templateId) {
    try {
      const params = {
        TableName: this.tableName,
        Key: { id: templateId }
      };

      const result = await docClient.send(new GetCommand(params));
      
      if (!result.Item) {
        throw new Error('Template not found');
      }

      if (!result.Item.isActive) {
        throw new Error('Template is inactive');
      }

      return result.Item;
    } catch (error) {
      logger.error('Error getting template', { templateId, error: error.message });
      throw error;
    }
  }

  async getTemplateByName(name) {
    try {
      const params = {
        TableName: this.tableName,
        IndexName: 'name-index',
        KeyConditionExpression: '#name = :name',
        ExpressionAttributeNames: {
          '#name': 'name'
        },
        ExpressionAttributeValues: {
          ':name': name
        }
      };

      const result = await docClient.send(new QueryCommand(params));
      
      if (result.Items.length === 0) {
        throw new Error('Template not found');
      }

      const activeTemplate = result.Items.find(template => template.isActive);
      if (!activeTemplate) {
        throw new Error('No active template found with this name');
      }

      return activeTemplate;
    } catch (error) {
      logger.error('Error getting template by name', { name, error: error.message });
      throw error;
    }
  }

  async updateTemplate(templateId, updateData) {
    try {
      // Get existing template first
      const existingTemplate = await this.getTemplate(templateId);
      const updatedTemplate = TemplateModel.update(existingTemplate, updateData);

      const params = {
        TableName: this.tableName,
        Key: { id: templateId },
        UpdateExpression: 'SET #name = :name, description = :description, #type = :type, subject = :subject, htmlBody = :htmlBody, textBody = :textBody, variables = :variables, category = :category, isActive = :isActive, metadata = :metadata, version = :version, updatedAt = :updatedAt',
        ExpressionAttributeNames: {
          '#name': 'name',
          '#type': 'type'
        },
        ExpressionAttributeValues: {
          ':name': updatedTemplate.name,
          ':description': updatedTemplate.description,
          ':type': updatedTemplate.type,
          ':subject': updatedTemplate.subject,
          ':htmlBody': updatedTemplate.htmlBody,
          ':textBody': updatedTemplate.textBody,
          ':variables': updatedTemplate.variables,
          ':category': updatedTemplate.category,
          ':isActive': updatedTemplate.isActive,
          ':metadata': updatedTemplate.metadata,
          ':version': updatedTemplate.version,
          ':updatedAt': updatedTemplate.updatedAt
        },
        ReturnValues: 'ALL_NEW'
      };

      const result = await docClient.send(new UpdateCommand(params));
      
      // Clear compiled template cache
      this.compiledTemplates.delete(templateId);
      
      logger.info('Template updated successfully', { templateId });
      return result.Attributes;
    } catch (error) {
      logger.error('Error updating template', { templateId, error: error.message });
      throw error;
    }
  }

  async deleteTemplate(templateId) {
    try {
      const params = {
        TableName: this.tableName,
        Key: { id: templateId },
        ConditionExpression: 'attribute_exists(id)'
      };

      await docClient.send(new DeleteCommand(params));
      
      // Clear compiled template cache
      this.compiledTemplates.delete(templateId);
      
      logger.info('Template deleted successfully', { templateId });
      return { success: true };
    } catch (error) {
      if (error.name === 'ConditionalCheckFailedException') {
        throw new Error('Template not found');
      }
      logger.error('Error deleting template', { templateId, error: error.message });
      throw error;
    }
  }

  async listTemplates(limit = 50, lastEvaluatedKey = null) {
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
        templates: result.Items || [],
        lastEvaluatedKey: result.LastEvaluatedKey
      };
    } catch (error) {
      logger.error('Error listing templates', { error: error.message });
      throw error;
    }
  }

  renderTemplate(template, variables = {}) {
    try {
      // Validate required variables
      TemplateModel.validateVariables(template, variables);

      // Add system variables
      const systemVariables = {
        ...variables,
        currentDate: new Date().toLocaleDateString(),
        currentTime: new Date().toLocaleTimeString(),
        currentYear: new Date().getFullYear()
      };

      // Get or compile templates
      const cacheKey = `${template.id}-${template.version}`;
      let compiledTemplate = this.compiledTemplates.get(cacheKey);

      if (!compiledTemplate) {
        compiledTemplate = {
          subject: template.subject ? Handlebars.compile(template.subject) : null,
          htmlBody: template.htmlBody ? Handlebars.compile(template.htmlBody) : null,
          textBody: Handlebars.compile(template.textBody)
        };
        this.compiledTemplates.set(cacheKey, compiledTemplate);
      }

      const rendered = {
        subject: compiledTemplate.subject ? compiledTemplate.subject(systemVariables) : null,
        html: compiledTemplate.htmlBody ? compiledTemplate.htmlBody(systemVariables) : null,
        text: compiledTemplate.textBody(systemVariables)
      };

      logger.debug('Template rendered successfully', { 
        templateId: template.id,
        variables: Object.keys(variables)
      });

      return rendered;
    } catch (error) {
      logger.error('Error rendering template', { 
        templateId: template.id,
        error: error.message 
      });
      throw error;
    }
  }

  async getTemplatesByCategory(category) {
    try {
      const params = {
        TableName: this.tableName,
        FilterExpression: 'category = :category AND isActive = :isActive',
        ExpressionAttributeValues: {
          ':category': category,
          ':isActive': true
        }
      };

      const result = await docClient.send(new ScanCommand(params));
      return result.Items || [];
    } catch (error) {
      logger.error('Error getting templates by category', { category, error: error.message });
      throw error;
    }
  }
}

module.exports = TemplateService;