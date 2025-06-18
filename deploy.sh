#!/bin/bash

# Notification Service Deployment Script
# This script builds and deploys the notification service using Terraform

set -e

echo "🚀 Starting Notification Service Deployment"

# Configuration
PROJECT_NAME="notification-service"
TERRAFORM_DIR="./terraform"
BUILD_DIR="./build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18.x or later."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    # Check if terraform.tfvars exists
    if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        print_error "terraform.tfvars not found. Please create it from terraform.tfvars.example"
        exit 1
    fi
    
    print_status "Prerequisites check passed ✅"
}

# Install dependencies
install_dependencies() {
    print_status "Installing Node.js dependencies..."
    npm install
    print_status "Dependencies installed ✅"
}

# Build the deployment package
build_deployment_package() {
    print_status "Building deployment package..."
    
    # Clean build directory
    rm -rf $BUILD_DIR
    mkdir -p $BUILD_DIR
    
    # Copy source files
    cp -r src $BUILD_DIR/
    cp package.json $BUILD_DIR/
    cp package-lock.json $BUILD_DIR/ 2>/dev/null || true
    
    # Install production dependencies
    cd $BUILD_DIR
    npm install --production --no-optional
    cd ..
    
    # Create deployment zip
    cd $BUILD_DIR
    zip -r ../$PROJECT_NAME.zip . -x "*.git*" "*.DS_Store*" "node_modules/.cache/*"
    cd ..
    
    print_status "Deployment package created: $PROJECT_NAME.zip ✅"
}

# Validate Terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    cd $TERRAFORM_DIR
    terraform fmt -check
    terraform validate
    cd ..
    print_status "Terraform validation passed ✅"
}

# Initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    cd $TERRAFORM_DIR
    terraform init
    cd ..
    print_status "Terraform initialized ✅"
}

# Plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    cd $TERRAFORM_DIR
    terraform plan -out=tfplan
    cd ..
    print_status "Terraform plan created ✅"
}

# Apply Terraform deployment
apply_terraform() {
    print_status "Applying Terraform deployment..."
    cd $TERRAFORM_DIR
    terraform apply tfplan
    cd ..
    print_status "Terraform deployment completed ✅"
}

# Get deployment outputs
get_outputs() {
    print_status "Getting deployment outputs..."
    cd $TERRAFORM_DIR
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Deployment Information:"
    echo "========================"
    terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
    echo ""
    cd ..
}

# Create sample data
create_sample_data() {
    print_status "Would you like to create sample templates and subscribers? (y/n)"
    read -r create_samples
    
    if [[ $create_samples == "y" || $create_samples == "Y" ]]; then
        print_status "Creating sample data..."
        
        # Get API Gateway URL
        cd $TERRAFORM_DIR
        API_URL=$(terraform output -raw api_gateway_url)
        cd ..
        
        # Create sample email template
        curl -X POST "$API_URL/templates" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Welcome Email",
                "description": "Welcome email for new subscribers",
                "type": "email",
                "subject": "Welcome {{firstName}}!",
                "htmlBody": "<h1>Welcome {{firstName}} {{lastName}}!</h1><p>Thank you for joining us on {{currentDate}}. We are excited to have you!</p>",
                "textBody": "Welcome {{firstName}} {{lastName}}! Thank you for joining us on {{currentDate}}. We are excited to have you!",
                "category": "onboarding"
            }' \
            --silent --show-error || print_warning "Failed to create email template"
        
        # Create sample SMS template
        curl -X POST "$API_URL/templates" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Welcome SMS",
                "description": "Welcome SMS for new subscribers",
                "type": "sms",
                "textBody": "Welcome {{firstName}}! Thanks for joining us. Reply STOP to unsubscribe.",
                "category": "onboarding"
            }' \
            --silent --show-error || print_warning "Failed to create SMS template"
        
        # Create sample subscriber
        curl -X POST "$API_URL/subscribers" \
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
            }' \
            --silent --show-error || print_warning "Failed to create sample subscriber"
        
        print_status "Sample data created ✅"
        echo ""
        echo "📚 API Documentation:"
        echo "===================="
        echo "API Base URL: $API_URL"
        echo ""
        echo "Send Notification:"
        echo "POST $API_URL/notifications"
        echo ""
        echo "Create Template:"
        echo "POST $API_URL/templates"
        echo ""
        echo "Create Subscriber:"
        echo "POST $API_URL/subscribers"
        echo ""
        echo "Health Check:"
        echo "GET $API_URL/health"
        echo ""
    fi
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf $BUILD_DIR
    rm -f $PROJECT_NAME.zip
    rm -f $TERRAFORM_DIR/tfplan
}

# Main deployment process
main() {
    echo "🔧 Production-Grade AWS Notification Service Deployment"
    echo "======================================================="
    echo ""
    
    # Add trap for cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    install_dependencies
    build_deployment_package
    validate_terraform
    init_terraform
    plan_terraform
    
    # Ask for confirmation before applying
    print_warning "Ready to deploy to AWS. This will create resources and may incur costs."
    echo "Do you want to continue? (y/n)"
    read -r confirm_deploy
    
    if [[ $confirm_deploy == "y" || $confirm_deploy == "Y" ]]; then
        apply_terraform
        get_outputs
        create_sample_data
        
        print_status "🎉 Deployment completed successfully!"
        print_status "📖 Check the documentation in README.md for API usage examples."
    else
        print_status "Deployment cancelled."
        exit 0
    fi
}

# Handle script arguments
case "${1:-}" in
    "clean")
        print_status "Cleaning up build artifacts..."
        cleanup
        ;;
    "build")
        check_prerequisites
        install_dependencies
        build_deployment_package
        ;;
    "plan")
        check_prerequisites
        install_dependencies
        build_deployment_package
        validate_terraform
        init_terraform
        plan_terraform
        ;;
    "destroy")
        print_warning "This will destroy all AWS resources. Are you sure? (y/n)"
        read -r confirm_destroy
        if [[ $confirm_destroy == "y" || $confirm_destroy == "Y" ]]; then
            cd $TERRAFORM_DIR
            terraform destroy
            cd ..
            print_status "Resources destroyed ✅"
        fi
        ;;
    *)
        main
        ;;
esac