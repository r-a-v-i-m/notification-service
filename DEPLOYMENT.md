# Deployment Guide for AWS Notification Service

This guide provides detailed instructions for deploying the production-grade AWS notification service using Terraform.

## 📋 Prerequisites

### Required Tools
- **AWS CLI** v2.x or later
- **Terraform** v1.5 or later  
- **Node.js** v18.x or later
- **jq** (for JSON processing)
- **Git** (for version control)

### AWS Requirements
- AWS Account with appropriate permissions
- Verified SES email address for sending notifications
- AWS CLI configured with credentials

## 🚀 Quick Start Deployment

### 1. Clone and Setup
```bash
git clone <repository-url>
cd notification-service
```

### 2. Configure AWS Credentials
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and region
```

### 3. Configure Terraform Variables
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your configuration:
```hcl
# AWS Configuration
aws_region = "us-east-1"
environment = "dev"
project_name = "notification-service"

# SES Configuration (REQUIRED)
ses_from_email = "your-verified-email@domain.com"

# Optional: Customize resource configuration
lambda_memory_size = 512
lambda_timeout = 30
enable_vpc = false
enable_encryption = true
```

### 4. Deploy Using Make Commands
```bash
# Option 1: Complete deployment workflow
make full-deploy

# Option 2: Step-by-step deployment
make install      # Install dependencies
make build        # Build Lambda package
make validate     # Validate Terraform
make plan         # Plan deployment
make deploy       # Deploy infrastructure
make test-api     # Test the deployment
```

### 5. Verify Deployment
```bash
# Check deployment status
make status

# Test API health
make quick-test

# View outputs
make outputs
```

## 📦 AWS Resources Created

### Core Infrastructure
- **3 Lambda Functions**: API handler, Stream processor, DLQ processor
- **3 DynamoDB Tables**: Subscribers, Templates, Outbox (with streams)
- **API Gateway**: REST API with throttling and monitoring
- **SQS Queue**: Dead letter queue for failed notifications
- **CloudWatch**: Log groups, metrics, and alarms

### Optional Infrastructure
- **VPC**: Private networking (if `enable_vpc = true`)
- **KMS Key**: Encryption at rest (if `enable_encryption = true`)
- **SNS Topic**: Operational notifications (production only)

### Estimated Monthly Costs
- **Development**: $20-50/month (low usage)
- **Production**: $100-500/month (depends on volume)

## 🔧 Configuration Options

### Environment Variables (terraform.tfvars)

#### AWS Configuration
```hcl
aws_region = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b"]
```

#### Project Settings
```hcl
project_name = "notification-service"
environment = "dev"  # dev, staging, prod
```

#### Lambda Configuration
```hcl
lambda_runtime = "nodejs18.x"
lambda_timeout = 30                    # seconds
lambda_memory_size = 512               # MB
lambda_reserved_concurrency = 100      # concurrent executions
```

#### DynamoDB Configuration
```hcl
dynamodb_billing_mode = "PAY_PER_REQUEST"  # or "PROVISIONED"
# dynamodb_read_capacity = 5             # only for PROVISIONED
# dynamodb_write_capacity = 5            # only for PROVISIONED
outbox_ttl_days = 7                     # auto-cleanup
```

#### Security Settings
```hcl
enable_vpc = false           # deploy in VPC for enhanced security
enable_encryption = true     # encrypt data at rest
enable_xray_tracing = true   # enable X-Ray distributed tracing
```

#### Monitoring Settings
```hcl
enable_detailed_monitoring = true
log_retention_days = 14      # CloudWatch log retention
```

#### API Gateway Settings
```hcl
api_gateway_throttle_burst_limit = 2000  # burst requests
api_gateway_throttle_rate_limit = 1000   # requests per second
```

### Resource Tagging
```hcl
tags = {
  Project     = "notification-service"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "team@company.com"
  CostCenter  = "engineering"
}
```

## 🏗️ Architecture Details

### Lambda Functions

#### API Handler (`api-handler.js`)
- **Purpose**: Handle REST API requests
- **Timeout**: 30 seconds
- **Memory**: 512 MB
- **Triggers**: API Gateway
- **Endpoints**: All CRUD operations

#### Stream Processor (`stream-processor.js`)
- **Purpose**: Process DynamoDB stream events (outbox pattern)
- **Timeout**: 60 seconds
- **Memory**: 512 MB
- **Triggers**: DynamoDB streams from outbox table
- **Function**: Send notifications via SES/SNS

#### DLQ Processor (`dlq-processor.js`)
- **Purpose**: Process failed notifications
- **Timeout**: 60 seconds
- **Memory**: 512 MB
- **Triggers**: SQS dead letter queue
- **Function**: Retry failed notifications with backoff

### DynamoDB Tables

#### Subscribers Table
```
Primary Key: id (String)
GSI: email-index, phone-index
Attributes: email, phone, firstName, lastName, preferences, metadata
```

#### Templates Table
```
Primary Key: id (String)
GSI: name-index, category-index
Attributes: name, type, subject, htmlBody, textBody, variables
```

#### Outbox Table
```
Primary Key: id (String)
GSI: status-index, notificationId-index, priority-index
Attributes: notificationId, type, recipient, content, status, priority
Features: DynamoDB streams, TTL (7 days)
```

## 🔒 Security Best Practices

### IAM Permissions
- Lambda functions use least-privilege IAM roles
- Separate policies for different AWS services
- No wildcard permissions in production

### Encryption
- DynamoDB tables encrypted at rest (optional)
- SQS messages encrypted with KMS (optional)
- CloudWatch logs encrypted (optional)

### VPC Deployment (Optional)
```hcl
enable_vpc = true
vpc_cidr = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
```

Benefits:
- Lambda functions in private subnets
- VPC endpoints for AWS services
- Enhanced network security
- No internet gateway access

### API Security
- API Gateway throttling enabled
- Request validation
- CORS configured
- CloudWatch access logging

## 📊 Monitoring & Observability

### CloudWatch Metrics
- Lambda function metrics (invocations, errors, duration)
- API Gateway metrics (requests, latency, errors)
- DynamoDB metrics (read/write capacity, throttling)
- Custom application metrics

### CloudWatch Alarms
- Lambda function errors
- API Gateway 4XX/5XX errors
- DynamoDB throttling
- SQS message age in DLQ

### X-Ray Tracing (Optional)
```hcl
enable_xray_tracing = true
```
- Distributed request tracing
- Performance analysis
- Error root cause analysis

### Log Aggregation
```bash
# View logs for all functions
make watch-logs

# View specific function logs
aws logs tail /aws/lambda/dev-notification-service-api --follow
```

## 🔄 Deployment Strategies

### Development Environment
```bash
# Quick development deployment
make dev-setup
make dev-deploy
```

### Staging Environment
```bash
# Switch to staging workspace
cd terraform
terraform workspace select staging || terraform workspace new staging
make deploy
```

### Production Environment
```bash
# Switch to production workspace
cd terraform
terraform workspace select prod || terraform workspace new prod

# Production-specific settings
export TF_VAR_environment=prod
export TF_VAR_enable_detailed_monitoring=true
export TF_VAR_log_retention_days=30

make deploy
```

### Blue-Green Deployment
1. Deploy to new environment
2. Test thoroughly
3. Update DNS/load balancer
4. Monitor and rollback if needed

## 🧪 Testing & Validation

### Automated Testing
```bash
# Run all tests
make full-test

# Individual test types
make test         # Unit tests
make test-api     # API integration tests
make quick-test   # Health check only
```

### Manual Testing
```bash
# Get API URL
API_URL=$(cd terraform && terraform output -raw api_gateway_url)

# Test health endpoint
curl $API_URL/health

# Create template
curl -X POST $API_URL/templates \
  -H "Content-Type: application/json" \
  -d '{"name":"test","type":"email","subject":"Hello","textBody":"Hello World"}'

# Send notification
curl -X POST $API_URL/notifications \
  -H "Content-Type: application/json" \
  -d '{"type":"email","recipient":"test@example.com","templateId":"<id>","variables":{}}'
```

### Load Testing
```bash
# Install artillery for load testing
npm install -g artillery

# Create artillery config
cat > load-test.yml << EOF
config:
  target: '$API_URL'
  phases:
    - duration: 60
      arrivalRate: 10
scenarios:
  - name: "Health check"
    requests:
      - get:
          url: "/health"
EOF

# Run load test
artillery run load-test.yml
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. SES Email Not Verified
```
Error: User `arn:aws:sts::account:assumed-role/...` is not authorized to perform `ses:SendEmail`
```
**Solution**: Verify your email in AWS SES console

#### 2. Lambda Timeout
```
Task timed out after 30.00 seconds
```
**Solution**: Increase `lambda_timeout` in terraform.tfvars

#### 3. DynamoDB Throttling
```
ProvisionedThroughputExceededException
```
**Solution**: Use `PAY_PER_REQUEST` billing mode or increase capacity

#### 4. API Gateway 5XX Errors
```
{"message": "Internal server error"}
```
**Solution**: Check Lambda function logs in CloudWatch

### Debugging Commands
```bash
# Check Lambda logs
make logs

# Get deployment status
make status

# Show Terraform outputs
make outputs

# Validate configuration
make validate

# Test API health
make quick-test
```

### State Management Issues
```bash
# Backup current state
make backup-state

# Import existing resources (if needed)
cd terraform
terraform import aws_dynamodb_table.subscribers table-name

# Refresh state
terraform refresh
```

## 🔄 Maintenance & Updates

### Regular Maintenance
```bash
# Update dependencies
npm update
npm audit fix

# Update Terraform providers
cd terraform
terraform init -upgrade

# Clean old resources
make clean
```

### Scaling Considerations
- **Lambda**: Adjust reserved concurrency based on load
- **DynamoDB**: Monitor and adjust capacity units
- **API Gateway**: Request limit increases if needed
- **SES**: Request sending limit increases

### Backup Strategy
```bash
# Backup Terraform state
make backup-state

# Export DynamoDB tables
aws dynamodb create-backup --table-name dev-notification-service-subscribers --backup-name backup-$(date +%Y%m%d)
```

## 🗑️ Cleanup & Destruction

### Destroy Infrastructure
```bash
# Destroy everything
make destroy

# Or using Terraform directly
cd terraform
terraform destroy -auto-approve
```

### Clean Local Files
```bash
# Clean build artifacts
make clean

# Remove all generated files
rm -rf build/
rm -f notification-service.zip
rm -rf terraform/.terraform/
rm -f terraform/terraform.tfstate*
```

## 📞 Support & Troubleshooting

### Logs Location
- **Lambda**: `/aws/lambda/function-name`
- **API Gateway**: `/aws/apigateway/api-name`

### Key Metrics to Monitor
- Lambda invocations and errors
- DynamoDB read/write capacity
- SQS message age
- API Gateway latency

### Getting Help
1. Check CloudWatch logs first
2. Verify AWS service limits
3. Review IAM permissions
4. Test individual components
5. Check the troubleshooting section above

For additional support, refer to the main README.md file for detailed API documentation and usage examples.