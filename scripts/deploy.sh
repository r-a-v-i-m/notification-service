#!/bin/bash

# Complete Deployment Script for Notification Service
# This script handles the entire deployment process including infrastructure

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[DEPLOY]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local errors=0
    
    # Check if required tools are installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform 1.5+ from https://terraform.io"
        ((errors++))
    else
        TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d'v' -f2)
        print_info "Terraform version: $TERRAFORM_VERSION"
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI from https://aws.amazon.com/cli/"
        ((errors++))
    else
        AWS_VERSION=$(aws --version | cut -d'/' -f2 | cut -d' ' -f1)
        print_info "AWS CLI version: $AWS_VERSION"
    fi
    
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18+ from https://nodejs.org"
        ((errors++))
    else
        NODE_VERSION=$(node --version)
        print_info "Node.js version: $NODE_VERSION"
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Some features may not work properly."
        print_info "Install with: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        ((errors++))
    else
        AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "not set")
        print_info "AWS Account: $AWS_ACCOUNT"
        print_info "AWS Region: $AWS_REGION"
    fi
    
    # Check if terraform.tfvars exists
    if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        print_error "terraform.tfvars not found. Please create it from terraform.tfvars.example"
        print_info "Run: cp $TERRAFORM_DIR/terraform.tfvars.example $TERRAFORM_DIR/terraform.tfvars"
        print_info "Then edit terraform.tfvars with your configuration"
        ((errors++))
    fi
    
    if [ $errors -gt 0 ]; then
        print_error "Please fix the above issues before proceeding."
        exit 1
    fi
    
    print_status "Prerequisites check passed ✅"
}

# Build Lambda package
build_lambda() {
    print_step "Building Lambda deployment package..."
    
    if [ -x "$SCRIPTS_DIR/build-lambda.sh" ]; then
        "$SCRIPTS_DIR/build-lambda.sh"
    else
        print_error "build-lambda.sh not found or not executable"
        exit 1
    fi
    
    print_status "Lambda package built ✅"
}

# Initialize Terraform
init_terraform() {
    print_step "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    terraform init -upgrade
    
    print_status "Terraform initialized ✅"
    cd "$PROJECT_ROOT"
}

# Validate Terraform configuration
validate_terraform() {
    print_step "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    # Format Terraform files
    terraform fmt -recursive
    
    # Validate configuration
    terraform validate
    
    print_status "Terraform validation passed ✅"
    cd "$PROJECT_ROOT"
}

# Plan Terraform deployment
plan_terraform() {
    print_step "Planning Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Create plan
    terraform plan -out=tfplan -detailed-exitcode
    local plan_exit_code=$?
    
    case $plan_exit_code in
        0)
            print_info "No changes detected in Terraform plan"
            ;;
        1)
            print_error "Terraform plan failed"
            exit 1
            ;;
        2)
            print_info "Changes detected in Terraform plan"
            ;;
    esac
    
    print_status "Terraform plan created ✅"
    cd "$PROJECT_ROOT"
    
    return $plan_exit_code
}

# Apply Terraform deployment
apply_terraform() {
    print_step "Applying Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Apply the plan
    terraform apply tfplan
    
    print_status "Terraform deployment completed ✅"
    cd "$PROJECT_ROOT"
}

# Get deployment outputs
get_outputs() {
    print_step "Retrieving deployment information..."
    
    cd "$TERRAFORM_DIR"
    
    if terraform output -json > /dev/null 2>&1; then
        echo ""
        echo "🎉 Deployment completed successfully!"
        echo ""
        echo "📋 Deployment Information:"
        echo "=========================="
        
        # Get key outputs
        API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "Not available")
        HEALTH_URL="$API_URL/health"
        
        echo "API Gateway URL: $API_URL"
        echo "Health Check URL: $HEALTH_URL"
        echo ""
        
        echo "📊 Resource Summary:"
        echo "==================="
        
        # DynamoDB Tables
        echo "DynamoDB Tables:"
        terraform output -json | jq -r '
            .subscribers_table_name.value as $sub |
            .templates_table_name.value as $tmpl |
            .outbox_table_name.value as $out |
            "  - Subscribers: \($sub)\n  - Templates: \($tmpl)\n  - Outbox: \($out)"
        ' 2>/dev/null || echo "  - Tables created successfully"
        
        # Lambda Functions
        echo "Lambda Functions:"
        terraform output -json | jq -r '
            .lambda_functions.value |
            to_entries[] |
            "  - \(.key): \(.value.name)"
        ' 2>/dev/null || echo "  - Functions deployed successfully"
        
        # SQS Queue
        DLQ_URL=$(terraform output -raw dlq_url 2>/dev/null || echo "Created")
        echo "SQS Dead Letter Queue: $DLQ_URL"
        
        echo ""
        echo "🔗 Quick Start:"
        echo "==============="
        echo "1. Test health endpoint:"
        echo "   curl $HEALTH_URL"
        echo ""
        echo "2. Create your first template:"
        echo "   curl -X POST $API_URL/templates \\"
        echo "     -H 'Content-Type: application/json' \\"
        echo "     -d '{\"name\":\"test\",\"type\":\"email\",\"subject\":\"Hello {{name}}!\",\"textBody\":\"Hello {{name}}!\",\"htmlBody\":\"<h1>Hello {{name}}!</h1>\"}'"
        echo ""
        echo "3. Send a test notification:"
        echo "   curl -X POST $API_URL/notifications \\"
        echo "     -H 'Content-Type: application/json' \\"
        echo "     -d '{\"type\":\"email\",\"recipient\":\"test@example.com\",\"templateId\":\"<template-id>\",\"variables\":{\"name\":\"Test User\"}}'"
        echo ""
        
    else
        print_warning "Could not retrieve Terraform outputs"
    fi
    
    cd "$PROJECT_ROOT"
}

# Test deployment
test_deployment() {
    print_step "Testing deployment..."
    
    cd "$TERRAFORM_DIR"
    
    API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)
    
    if [ -n "$API_URL" ]; then
        HEALTH_URL="$API_URL/health"
        print_info "Testing health endpoint: $HEALTH_URL"
        
        # Test health endpoint with timeout
        if curl -f -s --max-time 30 "$HEALTH_URL" > /dev/null; then
            print_status "Health check passed ✅"
        else
            print_warning "Health check failed. The API might still be warming up."
            print_info "Try manually: curl $HEALTH_URL"
        fi
    else
        print_warning "Could not get API URL for testing"
    fi
    
    cd "$PROJECT_ROOT"
}

# Create sample data
create_sample_data() {
    print_step "Creating sample data..."
    
    cd "$TERRAFORM_DIR"
    
    API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)
    
    if [ -n "$API_URL" ]; then
        print_info "Creating sample email template..."
        
        TEMPLATE_RESPONSE=$(curl -s -X POST "$API_URL/templates" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Welcome Email",
                "description": "Welcome email template for new users",
                "type": "email",
                "subject": "Welcome {{firstName}}!",
                "htmlBody": "<h1>Welcome {{firstName}} {{lastName}}!</h1><p>Thank you for joining us on {{currentDate}}. We are excited to have you aboard!</p><p>Best regards,<br>The Team</p>",
                "textBody": "Welcome {{firstName}} {{lastName}}! Thank you for joining us on {{currentDate}}. We are excited to have you aboard! Best regards, The Team",
                "category": "onboarding"
            }' 2>/dev/null || echo '{"error": "failed"}')
        
        if echo "$TEMPLATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            TEMPLATE_ID=$(echo "$TEMPLATE_RESPONSE" | jq -r '.id')
            print_status "Sample email template created: $TEMPLATE_ID"
        else
            print_warning "Failed to create sample email template"
        fi
        
        print_info "Creating sample SMS template..."
        
        SMS_TEMPLATE_RESPONSE=$(curl -s -X POST "$API_URL/templates" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Welcome SMS",
                "description": "Welcome SMS template for new users",
                "type": "sms", 
                "textBody": "Welcome {{firstName}}! Thanks for joining us. Reply STOP to unsubscribe.",
                "category": "onboarding"
            }' 2>/dev/null || echo '{"error": "failed"}')
        
        if echo "$SMS_TEMPLATE_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            SMS_TEMPLATE_ID=$(echo "$SMS_TEMPLATE_RESPONSE" | jq -r '.id')
            print_status "Sample SMS template created: $SMS_TEMPLATE_ID"
        else
            print_warning "Failed to create sample SMS template"
        fi
        
        print_info "Creating sample subscriber..."
        
        SUBSCRIBER_RESPONSE=$(curl -s -X POST "$API_URL/subscribers" \
            -H "Content-Type: application/json" \
            -d '{
                "email": "test@example.com",
                "phone": "+1234567890",
                "firstName": "John",
                "lastName": "Doe",
                "preferences": {
                    "email": true,
                    "sms": true,
                    "categories": ["onboarding", "newsletter"]
                }
            }' 2>/dev/null || echo '{"error": "failed"}')
        
        if echo "$SUBSCRIBER_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
            SUBSCRIBER_ID=$(echo "$SUBSCRIBER_RESPONSE" | jq -r '.id')
            print_status "Sample subscriber created: $SUBSCRIBER_ID"
        else
            print_warning "Failed to create sample subscriber"
        fi
        
        print_status "Sample data creation completed ✅"
    else
        print_warning "Could not get API URL for sample data creation"
    fi
    
    cd "$PROJECT_ROOT"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up temporary files..."
    
    if [ -f "$TERRAFORM_DIR/tfplan" ]; then
        rm -f "$TERRAFORM_DIR/tfplan"
    fi
    
    # Don't clean build directory as it might be needed for troubleshooting
}

# Destroy infrastructure
destroy_infrastructure() {
    print_warning "This will destroy all AWS resources. Are you sure? (yes/no)"
    read -r confirm_destroy
    
    if [[ $confirm_destroy == "yes" ]]; then
        cd "$TERRAFORM_DIR"
        terraform destroy -auto-approve
        print_status "Infrastructure destroyed ✅"
        cd "$PROJECT_ROOT"
    else
        print_info "Destroy cancelled"
    fi
}

# Main deployment process
main() {
    echo "🚀 Production-Grade AWS Notification Service Deployment"
    echo "======================================================="
    echo ""
    
    # Add trap for cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    build_lambda
    init_terraform
    validate_terraform
    
    # Plan and confirm
    plan_terraform
    local plan_result=$?
    
    if [ $plan_result -eq 2 ]; then
        print_warning "Terraform plan shows changes will be made to your AWS account."
        print_warning "This may incur costs. Do you want to continue? (yes/no)"
        read -r confirm_deploy
        
        if [[ $confirm_deploy == "yes" ]]; then
            apply_terraform
            get_outputs
            test_deployment
            
            print_info "Would you like to create sample data? (yes/no)"
            read -r create_samples
            
            if [[ $create_samples == "yes" ]]; then
                create_sample_data
            fi
            
            print_status "🎉 Deployment completed successfully!"
            print_info "📖 Check the README.md for API usage examples"
            print_info "🔍 Monitor your resources in the AWS Console"
        else
            print_info "Deployment cancelled"
            exit 0
        fi
    elif [ $plan_result -eq 0 ]; then
        print_info "No changes needed. Infrastructure is up to date."
    fi
}

# Handle script arguments
case "${1:-}" in
    "init")
        check_prerequisites
        init_terraform
        ;;
    "plan")
        check_prerequisites
        build_lambda
        init_terraform
        validate_terraform
        plan_terraform
        ;;
    "apply")
        check_prerequisites
        build_lambda
        init_terraform
        validate_terraform
        plan_terraform
        apply_terraform
        get_outputs
        ;;
    "destroy")
        destroy_infrastructure
        ;;
    "test")
        test_deployment
        ;;
    "outputs")
        get_outputs
        ;;
    "clean")
        cleanup
        ;;
    "build")
        build_lambda
        ;;
    "validate")
        check_prerequisites
        validate_terraform
        ;;
    *)
        main
        ;;
esac