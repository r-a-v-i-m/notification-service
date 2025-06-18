const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');
const { SESClient } = require('@aws-sdk/client-ses');
const { SNSClient } = require('@aws-sdk/client-sns');
const { SQSClient } = require('@aws-sdk/client-sqs');
const { CloudWatchClient } = require('@aws-sdk/client-cloudwatch');

// Configure AWS SDK with retry configuration
const AWS_CONFIG = {
  region: process.env.AWS_REGION || 'us-east-1',
  maxAttempts: 3,
  retryMode: 'adaptive'
};

// Initialize AWS clients
const dynamoClient = new DynamoDBClient(AWS_CONFIG);
const docClient = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    convertEmptyValues: false,
    removeUndefinedValues: true,
    convertClassInstanceToMap: false
  },
  unmarshallOptions: {
    wrapNumbers: false
  }
});

const sesClient = new SESClient(AWS_CONFIG);
const snsClient = new SNSClient(AWS_CONFIG);
const sqsClient = new SQSClient(AWS_CONFIG);
const cloudwatchClient = new CloudWatchClient(AWS_CONFIG);

module.exports = {
  docClient,
  sesClient,
  snsClient,
  sqsClient,
  cloudwatchClient
};