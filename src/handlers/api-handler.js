const NotificationService = require('../services/notification-service');
const TemplateService = require('../services/template-service');
const SubscriberService = require('../services/subscriber-service');
const OutboxService = require('../services/outbox-service');
const ValidationHelper = require('../utils/validation');
const MetricsService = require('../services/metrics-service');
const logger = require('../utils/logger');

class ApiHandler {
  constructor() {
    this.notificationService = new NotificationService();
    this.templateService = new TemplateService();
    this.subscriberService = new SubscriberService();
    this.outboxService = new OutboxService();
    this.metricsService = new MetricsService();
  }

  async handler(event, context) {
    const startTime = Date.now();
    logger.addRequestId(context.awsRequestId);

    const headers = {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-API-Key'
    };

    try {
      const { httpMethod, path, body, queryStringParameters } = event;
      const parsedBody = body ? JSON.parse(body) : {};
      const queryParams = queryStringParameters || {};

      logger.info('API request received', {
        method: httpMethod,
        path,
        queryParams,
        hasBody: !!body
      });

      // Handle CORS preflight
      if (httpMethod === 'OPTIONS') {
        return this.createResponse(200, { message: 'CORS preflight' }, headers);
      }

      // Route requests
      const response = await this.routeRequest(httpMethod, path, parsedBody, queryParams);
      
      // Record metrics
      const duration = Date.now() - startTime;
      await this.metricsService.recordApiRequest(path, httpMethod, response.statusCode, duration);

      return { ...response, headers };

    } catch (error) {
      logger.error('API request failed', {
        error: error.message,
        stack: error.stack,
        event: JSON.stringify(event, null, 2)
      });

      const errorResponse = ValidationHelper.createErrorResponse(error, 500);
      
      const duration = Date.now() - startTime;
      await this.metricsService.recordApiRequest(
        event.path || 'unknown', 
        event.httpMethod || 'unknown', 
        errorResponse.statusCode, 
        duration
      );

      return this.createResponse(errorResponse.statusCode, errorResponse, headers);
    }
  }

  async routeRequest(method, path, body, queryParams) {
    const pathSegments = path.split('/').filter(segment => segment !== '');

    // Notification endpoints
    if (method === 'POST' && pathSegments[0] === 'notifications') {
      return await this.handleSendNotification(body);
    }

    if (method === 'POST' && pathSegments[0] === 'notifications' && pathSegments[1] === 'bulk') {
      return await this.handleBulkNotifications(body);
    }

    if (method === 'GET' && pathSegments[0] === 'notifications' && pathSegments[1]) {
      return await this.handleGetNotificationStatus(pathSegments[1]);
    }

    if (method === 'POST' && pathSegments[0] === 'notifications' && pathSegments[1] === 'retry') {
      return await this.handleRetryFailedNotifications();
    }

    // Template endpoints
    if (method === 'POST' && pathSegments[0] === 'templates') {
      return await this.handleCreateTemplate(body);
    }

    if (method === 'GET' && pathSegments[0] === 'templates' && !pathSegments[1]) {
      return await this.handleListTemplates(queryParams);
    }

    if (method === 'GET' && pathSegments[0] === 'templates' && pathSegments[1]) {
      return await this.handleGetTemplate(pathSegments[1]);
    }

    if (method === 'PUT' && pathSegments[0] === 'templates' && pathSegments[1]) {
      return await this.handleUpdateTemplate(pathSegments[1], body);
    }

    if (method === 'DELETE' && pathSegments[0] === 'templates' && pathSegments[1]) {
      return await this.handleDeleteTemplate(pathSegments[1]);
    }

    // Subscriber endpoints
    if (method === 'POST' && pathSegments[0] === 'subscribers') {
      return await this.handleCreateSubscriber(body);
    }

    if (method === 'GET' && pathSegments[0] === 'subscribers' && !pathSegments[1]) {
      return await this.handleListSubscribers(queryParams);
    }

    if (method === 'GET' && pathSegments[0] === 'subscribers' && pathSegments[1]) {
      return await this.handleGetSubscriber(pathSegments[1]);
    }

    if (method === 'PUT' && pathSegments[0] === 'subscribers' && pathSegments[1]) {
      return await this.handleUpdateSubscriber(pathSegments[1], body);
    }

    if (method === 'DELETE' && pathSegments[0] === 'subscribers' && pathSegments[1]) {
      return await this.handleDeleteSubscriber(pathSegments[1]);
    }

    // Health and stats endpoints
    if (method === 'GET' && pathSegments[0] === 'health') {
      return await this.handleHealthCheck();
    }

    if (method === 'GET' && pathSegments[0] === 'stats') {
      return await this.handleGetStats();
    }

    // Outbox management
    if (method === 'GET' && pathSegments[0] === 'outbox' && pathSegments[1] === 'failed') {
      return await this.handleGetFailedNotifications();
    }

    if (method === 'POST' && pathSegments[0] === 'outbox' && pathSegments[1] === 'requeue' && pathSegments[2]) {
      return await this.handleRequeueNotification(pathSegments[2]);
    }

    return this.createResponse(404, { error: 'Endpoint not found' });
  }

  // Notification handlers
  async handleSendNotification(body) {
    const { error, value } = ValidationHelper.validateNotificationRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const result = await this.notificationService.sendNotification(value);
    return this.createResponse(200, result);
  }

  async handleBulkNotifications(body) {
    const { error, value } = ValidationHelper.validateBulkNotificationRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const result = await this.notificationService.sendBulkNotifications(value.notifications);
    return this.createResponse(200, result);
  }

  async handleGetNotificationStatus(notificationId) {
    if (!ValidationHelper.validateUUID(notificationId)) {
      return this.createResponse(400, { error: 'Invalid notification ID format' });
    }

    const status = await this.notificationService.getNotificationStatus(notificationId);
    return this.createResponse(200, status);
  }

  async handleRetryFailedNotifications() {
    const result = await this.notificationService.retryFailedNotifications();
    return this.createResponse(200, result);
  }

  // Template handlers
  async handleCreateTemplate(body) {
    const { error, value } = ValidationHelper.validateTemplateRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const template = await this.templateService.createTemplate(value);
    return this.createResponse(201, template);
  }

  async handleListTemplates(queryParams) {
    const { error, value } = ValidationHelper.validatePaginationParams(queryParams);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const result = await this.templateService.listTemplates(value.limit, value.lastKey);
    return this.createResponse(200, result);
  }

  async handleGetTemplate(templateId) {
    if (!ValidationHelper.validateUUID(templateId)) {
      return this.createResponse(400, { error: 'Invalid template ID format' });
    }

    const template = await this.templateService.getTemplate(templateId);
    return this.createResponse(200, template);
  }

  async handleUpdateTemplate(templateId, body) {
    if (!ValidationHelper.validateUUID(templateId)) {
      return this.createResponse(400, { error: 'Invalid template ID format' });
    }

    const { error, value } = ValidationHelper.validateTemplateRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const template = await this.templateService.updateTemplate(templateId, value);
    return this.createResponse(200, template);
  }

  async handleDeleteTemplate(templateId) {
    if (!ValidationHelper.validateUUID(templateId)) {
      return this.createResponse(400, { error: 'Invalid template ID format' });
    }

    const result = await this.templateService.deleteTemplate(templateId);
    return this.createResponse(200, result);
  }

  // Subscriber handlers
  async handleCreateSubscriber(body) {
    const { error, value } = ValidationHelper.validateSubscriberRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const subscriber = await this.subscriberService.createSubscriber(value);
    return this.createResponse(201, subscriber);
  }

  async handleListSubscribers(queryParams) {
    const { error, value } = ValidationHelper.validatePaginationParams(queryParams);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const result = await this.subscriberService.listSubscribers(value.limit, value.lastKey);
    return this.createResponse(200, result);
  }

  async handleGetSubscriber(subscriberId) {
    if (!ValidationHelper.validateUUID(subscriberId)) {
      return this.createResponse(400, { error: 'Invalid subscriber ID format' });
    }

    const subscriber = await this.subscriberService.getSubscriber(subscriberId);
    return this.createResponse(200, subscriber);
  }

  async handleUpdateSubscriber(subscriberId, body) {
    if (!ValidationHelper.validateUUID(subscriberId)) {
      return this.createResponse(400, { error: 'Invalid subscriber ID format' });
    }

    const { error, value } = ValidationHelper.validateSubscriberRequest(body);
    if (error) {
      return this.createResponse(400, ValidationHelper.createErrorResponse(error));
    }

    const subscriber = await this.subscriberService.updateSubscriber(subscriberId, value);
    return this.createResponse(200, subscriber);
  }

  async handleDeleteSubscriber(subscriberId) {
    if (!ValidationHelper.validateUUID(subscriberId)) {
      return this.createResponse(400, { error: 'Invalid subscriber ID format' });
    }

    const result = await this.subscriberService.deleteSubscriber(subscriberId);
    return this.createResponse(200, result);
  }

  // System handlers
  async handleHealthCheck() {
    return this.createResponse(200, {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      environment: process.env.ENVIRONMENT || 'unknown'
    });
  }

  async handleGetStats() {
    const outboxStats = await this.outboxService.getOutboxStats();
    return this.createResponse(200, {
      outbox: outboxStats,
      timestamp: new Date().toISOString()
    });
  }

  async handleGetFailedNotifications() {
    const failedNotifications = await this.outboxService.getFailedNotifications();
    return this.createResponse(200, { 
      failed: failedNotifications,
      count: failedNotifications.length 
    });
  }

  async handleRequeueNotification(outboxId) {
    if (!ValidationHelper.validateUUID(outboxId)) {
      return this.createResponse(400, { error: 'Invalid outbox ID format' });
    }

    const result = await this.outboxService.requeueFailedNotification(outboxId);
    return this.createResponse(200, result);
  }

  createResponse(statusCode, body, additionalHeaders = {}) {
    return {
      statusCode,
      body: JSON.stringify(body),
      headers: {
        'Content-Type': 'application/json',
        ...additionalHeaders
      }
    };
  }
}

const apiHandler = new ApiHandler();
exports.handler = apiHandler.handler.bind(apiHandler);