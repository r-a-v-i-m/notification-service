# Makefile for Notification Service
# Provides common commands for development and deployment

.PHONY: help install build test validate plan deploy destroy clean logs status

# Default target
help: ## Show this help message
	@echo "Notification Service - Available Commands:"
	@echo "=========================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Development commands
install: ## Install dependencies
	@echo "📦 Installing dependencies..."
	npm install
	@echo "✅ Dependencies installed"

build: ## Build Lambda deployment package
	@echo "🔨 Building Lambda package..."
	./scripts/build-lambda.sh
	@echo "✅ Lambda package built"

test: ## Run tests
	@echo "🧪 Running tests..."
	npm test
	@echo "✅ Tests completed"

lint: ## Run linter
	@echo "🔍 Running linter..."
	npm run lint
	@echo "✅ Linting completed"

# Infrastructure commands  
validate: ## Validate Terraform configuration
	@echo "✅ Validating Terraform configuration..."
	./scripts/deploy.sh validate
	@echo "✅ Validation completed"

plan: ## Plan Terraform deployment
	@echo "📋 Planning Terraform deployment..."
	./scripts/deploy.sh plan
	@echo "✅ Planning completed"

deploy: ## Deploy infrastructure and application
	@echo "🚀 Deploying notification service..."
	./scripts/deploy.sh
	@echo "✅ Deployment completed"

destroy: ## Destroy infrastructure
	@echo "💥 Destroying infrastructure..."
	./scripts/deploy.sh destroy
	@echo "✅ Infrastructure destroyed"

# Utility commands
clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -rf build/
	rm -f notification-service.zip
	rm -f terraform/tfplan
	@echo "✅ Cleanup completed"

logs: ## Show recent CloudWatch logs
	@echo "📋 Showing recent logs..."
	@cd terraform && \
	API_FUNCTION=$$(terraform output -raw lambda_functions | jq -r '.api_handler.name' 2>/dev/null) && \
	if [ -n "$$API_FUNCTION" ]; then \
		aws logs tail "/aws/lambda/$$API_FUNCTION" --follow; \
	else \
		echo "❌ Could not get Lambda function name"; \
	fi

status: ## Show deployment status
	@echo "📊 Deployment Status:"
	@echo "===================="
	@cd terraform && \
	if [ -f terraform.tfstate ]; then \
		echo "✅ Infrastructure deployed"; \
		API_URL=$$(terraform output -raw api_gateway_url 2>/dev/null); \
		if [ -n "$$API_URL" ]; then \
			echo "🌐 API URL: $$API_URL"; \
			echo "🏥 Health: $$API_URL/health"; \
			echo ""; \
			echo "Testing health endpoint..."; \
			if curl -f -s --max-time 10 "$$API_URL/health" > /dev/null; then \
				echo "✅ API is responding"; \
			else \
				echo "❌ API is not responding"; \
			fi; \
		else \
			echo "❌ Could not get API URL"; \
		fi; \
	else \
		echo "❌ Infrastructure not deployed"; \
	fi

outputs: ## Show Terraform outputs
	@echo "📋 Terraform Outputs:"
	@echo "===================="
	@cd terraform && terraform output

test-api: ## Test API endpoints
	@echo "🧪 Testing API endpoints..."
	./scripts/test-api.sh
	@echo "✅ API testing completed"

quick-test: ## Quick API health test
	@echo "🚀 Quick API test..."
	./scripts/test-api.sh quick
	@echo "✅ Quick test completed"

# Development workflow commands
dev-setup: ## Complete development setup
	@echo "🔧 Setting up development environment..."
	make install
	make build
	make validate
	@echo "✅ Development setup completed"

dev-deploy: ## Development deployment workflow
	@echo "🚀 Development deployment workflow..."
	make build
	make validate
	make plan
	make deploy
	make test-api
	@echo "✅ Development deployment completed"

# CI/CD commands
ci-test: ## CI testing pipeline
	@echo "🤖 Running CI tests..."
	make install
	make lint
	make test
	make build
	make validate
	@echo "✅ CI tests completed"

cd-deploy: ## CD deployment pipeline
	@echo "🚀 Running CD deployment..."
	make build
	make plan
	make deploy
	make test-api
	@echo "✅ CD deployment completed"

# Monitoring commands
watch-logs: ## Watch CloudWatch logs in real-time
	@echo "👀 Watching logs..."
	@cd terraform && \
	API_FUNCTION=$$(terraform output -raw lambda_functions | jq -r '.api_handler.name' 2>/dev/null) && \
	STREAM_FUNCTION=$$(terraform output -raw lambda_functions | jq -r '.stream_processor.name' 2>/dev/null) && \
	DLQ_FUNCTION=$$(terraform output -raw lambda_functions | jq -r '.dlq_processor.name' 2>/dev/null) && \
	if [ -n "$$API_FUNCTION" ]; then \
		echo "Watching logs for all Lambda functions..."; \
		aws logs tail "/aws/lambda/$$API_FUNCTION" "/aws/lambda/$$STREAM_FUNCTION" "/aws/lambda/$$DLQ_FUNCTION" --follow; \
	else \
		echo "❌ Could not get Lambda function names"; \
	fi

metrics: ## Show CloudWatch metrics
	@echo "📊 CloudWatch Metrics:"
	@echo "====================="
	@cd terraform && \
	API_FUNCTION=$$(terraform output -raw lambda_functions | jq -r '.api_handler.name' 2>/dev/null) && \
	if [ -n "$$API_FUNCTION" ]; then \
		echo "Lambda Invocations (last 24h):"; \
		aws cloudwatch get-metric-statistics \
			--namespace AWS/Lambda \
			--metric-name Invocations \
			--dimensions Name=FunctionName,Value=$$API_FUNCTION \
			--start-time $$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%S) \
			--end-time $$(date -u +%Y-%m-%dT%H:%M:%S) \
			--period 3600 \
			--statistics Sum \
			--query 'Datapoints[0].Sum' \
			--output text 2>/dev/null || echo "No data"; \
	else \
		echo "❌ Could not get Lambda function name"; \
	fi

# Documentation commands
docs: ## Generate documentation
	@echo "📚 Generating documentation..."
	@echo "API Documentation available in README.md"
	@echo "Terraform documentation:"
	@cd terraform && terraform-docs markdown table . > TERRAFORM.md 2>/dev/null || echo "terraform-docs not installed"
	@echo "✅ Documentation updated"

# Security commands
security-scan: ## Run security scan
	@echo "🔒 Running security scan..."
	@if command -v npm audit >/dev/null 2>&1; then \
		echo "Scanning npm dependencies..."; \
		npm audit; \
	fi
	@if command -v checkov >/dev/null 2>&1; then \
		echo "Scanning Terraform configuration..."; \
		checkov -d terraform/; \
	else \
		echo "💡 Install checkov for Terraform security scanning: pip install checkov"; \
	fi
	@echo "✅ Security scan completed"

# Backup commands
backup-state: ## Backup Terraform state
	@echo "💾 Backing up Terraform state..."
	@cd terraform && \
	if [ -f terraform.tfstate ]; then \
		cp terraform.tfstate "terraform.tfstate.backup.$$(date +%Y%m%d-%H%M%S)"; \
		echo "✅ State backed up"; \
	else \
		echo "❌ No state file found"; \
	fi

# Environment-specific commands
deploy-dev: ## Deploy to development environment
	@echo "🚀 Deploying to development..."
	@cd terraform && \
	terraform workspace select dev 2>/dev/null || terraform workspace new dev
	make deploy
	@echo "✅ Development deployment completed"

deploy-prod: ## Deploy to production environment  
	@echo "🚀 Deploying to production..."
	@cd terraform && \
	terraform workspace select prod 2>/dev/null || terraform workspace new prod
	make deploy
	@echo "✅ Production deployment completed"

# Cost commands
cost-estimate: ## Estimate infrastructure costs
	@echo "💰 Estimating costs..."
	@if command -v infracost >/dev/null 2>&1; then \
		cd terraform && infracost breakdown --path .; \
	else \
		echo "💡 Install infracost for cost estimation: https://www.infracost.io/docs/"; \
		echo "💡 Alternative: Use AWS Pricing Calculator"; \
	fi

# Complete workflows
full-deploy: dev-setup dev-deploy ## Complete deployment workflow
	@echo "🎉 Full deployment completed!"

full-test: ## Complete testing workflow
	@echo "🧪 Running complete test suite..."
	make ci-test
	make test-api
	@echo "✅ Complete testing finished"