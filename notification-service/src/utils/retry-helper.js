const logger = require('./logger');

class RetryHelper {
  static async exponentialBackoff(
    fn,
    maxRetries = 3,
    baseDelay = 1000,
    maxDelay = 30000,
    factor = 2,
    jitter = true
  ) {
    let lastError;
    
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;
        
        if (attempt === maxRetries) {
          logger.error('Max retries exceeded', {
            attempts: attempt + 1,
            error: error.message
          });
          throw error;
        }

        // Calculate delay with exponential backoff
        let delay = Math.min(baseDelay * Math.pow(factor, attempt), maxDelay);
        
        // Add jitter to prevent thundering herd
        if (jitter) {
          delay = delay * (0.5 + Math.random() * 0.5);
        }

        logger.warn('Operation failed, retrying', {
          attempt: attempt + 1,
          maxRetries: maxRetries + 1,
          delay: Math.round(delay),
          error: error.message
        });

        await this.sleep(delay);
      }
    }
    
    throw lastError;
  }

  static async sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  static isRetryableError(error) {
    // Define which errors are retryable
    const retryableErrors = [
      'ThrottlingException',
      'ProvisionedThroughputExceededException',
      'ServiceUnavailableException',
      'InternalServerErrorException',
      'RequestTimeout',
      'NetworkingError',
      'ECONNRESET',
      'ENOTFOUND',
      'ECONNREFUSED',
      'ETIMEDOUT'
    ];

    const errorName = error.name || error.constructor.name;
    const errorMessage = error.message || '';
    
    return retryableErrors.some(retryableError => 
      errorName.includes(retryableError) || errorMessage.includes(retryableError)
    );
  }

  static async withRetry(operation, options = {}) {
    const {
      maxRetries = 3,
      baseDelay = 1000,
      maxDelay = 30000,
      factor = 2,
      jitter = true,
      retryCondition = this.isRetryableError
    } = options;

    const wrappedOperation = async () => {
      try {
        return await operation();
      } catch (error) {
        if (!retryCondition(error)) {
          throw error;
        }
        throw error;
      }
    };

    return this.exponentialBackoff(
      wrappedOperation,
      maxRetries,
      baseDelay,
      maxDelay,
      factor,
      jitter
    );
  }

  static async retryWithBackoff(operation, context = {}) {
    return this.withRetry(operation, {
      maxRetries: 3,
      baseDelay: 1000,
      retryCondition: (error) => {
        logger.debug('Evaluating retry condition', {
          errorName: error.name,
          errorMessage: error.message,
          context
        });
        return this.isRetryableError(error);
      }
    });
  }
}

module.exports = RetryHelper;