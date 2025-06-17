#!/bin/bash

# API Testing Script for Notification Service
# This script tests all API endpoints

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${PURPLE}[INFO]${NC} $1"
}

# Get API URL from Terraform output
get_api_url() {
    if [ -d "$TERRAFORM_DIR" ] && [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        cd "$TERRAFORM_DIR"
        API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)
        cd "$PROJECT_ROOT"
        
        if [ -n "$API_URL" ]; then
            echo "$API_URL"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Test API endpoint
test_endpoint() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local expected_status="$4"
    local description="$5"
    
    print_test "$description"
    
    local curl_cmd="curl -s -w '\n%{http_code}' -X $method"
    
    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -H 'Content-Type: application/json' -d '$data'"
    fi
    
    curl_cmd="$curl_cmd '$API_URL$endpoint'"
    
    local response
    response=$(eval "$curl_cmd")
    
    local body=$(echo "$response" | head -n -1)
    local status_code=$(echo "$response" | tail -n 1)
    
    if [ "$status_code" -eq "$expected_status" ]; then
        print_pass "Status: $status_code (Expected: $expected_status)"
        
        # Try to parse JSON response
        if echo "$body" | jq . > /dev/null 2>&1; then
            print_info "Response: $(echo "$body" | jq -c .)"
        else
            print_info "Response: $body"
        fi
        
        return 0
    else
        print_fail "Status: $status_code (Expected: $expected_status)"
        print_info "Response: $body"
        return 1
    fi
}

# Test health endpoint
test_health() {
    print_test "Testing health endpoint..."
    test_endpoint "GET" "/health" "" "200" "Health check"
}

# Test template creation
test_create_template() {
    print_test "Testing template creation..."
    
    local template_data='{
        "name": "Test Email Template",
        "description": "Test email template for API testing",
        "type": "email",
        "subject": "Test Subject {{name}}",
        "htmlBody": "<h1>Hello {{name}}!</h1><p>This is a test email.</p>",
        "textBody": "Hello {{name}}! This is a test email.",
        "category": "test"
    }'
    
    local response
    response=$(curl -s -X POST "$API_URL/templates" \
        -H "Content-Type: application/json" \
        -d "$template_data")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        TEMPLATE_ID=$(echo "$response" | jq -r '.id')
        print_pass "Template created with ID: $TEMPLATE_ID"
        return 0
    else
        print_fail "Failed to create template"
        print_info "Response: $response"
        return 1
    fi
}

# Test template retrieval
test_get_template() {
    if [ -n "$TEMPLATE_ID" ]; then
        print_test "Testing template retrieval..."
        test_endpoint "GET" "/templates/$TEMPLATE_ID" "" "200" "Get template by ID"
    else
        print_info "Skipping template retrieval test (no template ID)"
    fi
}

# Test template listing
test_list_templates() {
    print_test "Testing template listing..."
    test_endpoint "GET" "/templates" "" "200" "List templates"
}

# Test subscriber creation
test_create_subscriber() {
    print_test "Testing subscriber creation..."
    
    local subscriber_data='{
        "email": "test@example.com",
        "phone": "+1234567890",
        "firstName": "Test",
        "lastName": "User",
        "preferences": {
            "email": true,
            "sms": true,
            "categories": ["test"]
        }
    }'
    
    local response
    response=$(curl -s -X POST "$API_URL/subscribers" \
        -H "Content-Type: application/json" \
        -d "$subscriber_data")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        SUBSCRIBER_ID=$(echo "$response" | jq -r '.id')
        print_pass "Subscriber created with ID: $SUBSCRIBER_ID"
        return 0
    else
        print_fail "Failed to create subscriber"
        print_info "Response: $response"
        return 1
    fi
}

# Test subscriber retrieval
test_get_subscriber() {
    if [ -n "$SUBSCRIBER_ID" ]; then
        print_test "Testing subscriber retrieval..."
        test_endpoint "GET" "/subscribers/$SUBSCRIBER_ID" "" "200" "Get subscriber by ID"
    else
        print_info "Skipping subscriber retrieval test (no subscriber ID)"
    fi
}

# Test subscriber listing
test_list_subscribers() {
    print_test "Testing subscriber listing..."
    test_endpoint "GET" "/subscribers" "" "200" "List subscribers"
}

# Test notification sending (will fail without verified SES email)
test_send_notification() {
    if [ -n "$TEMPLATE_ID" ]; then
        print_test "Testing notification sending..."
        
        local notification_data='{
            "type": "email",
            "recipient": "test@example.com",
            "templateId": "'$TEMPLATE_ID'",
            "variables": {
                "name": "Test User"
            }
        }'
        
        # This will likely fail if SES email is not verified, but that is expected
        local response
        response=$(curl -s -w '\n%{http_code}' -X POST "$API_URL/notifications" \
            -H "Content-Type: application/json" \
            -d "$notification_data")
        
        local body=$(echo "$response" | head -n -1)
        local status_code=$(echo "$response" | tail -n 1)
        
        if [ "$status_code" -eq "200" ]; then
            print_pass "Notification queued successfully"
            print_info "Response: $(echo "$body" | jq -c .)"
        else
            print_info "Notification failed (expected if SES email not verified)"
            print_info "Status: $status_code"
            print_info "Response: $body"
        fi
    else
        print_info "Skipping notification test (no template ID)"
    fi
}

# Test statistics endpoint
test_stats() {
    print_test "Testing statistics endpoint..."
    test_endpoint "GET" "/stats" "" "200" "Get system statistics"
}

# Test invalid endpoints
test_invalid_endpoints() {
    print_test "Testing invalid endpoints..."
    test_endpoint "GET" "/invalid-endpoint" "" "404" "Invalid endpoint should return 404"
}

# Clean up test data
cleanup_test_data() {
    print_test "Cleaning up test data..."
    
    # Delete test template if created
    if [ -n "$TEMPLATE_ID" ]; then
        curl -s -X DELETE "$API_URL/templates/$TEMPLATE_ID" > /dev/null 2>&1 || true
        print_info "Test template cleanup attempted"
    fi
    
    # Delete test subscriber if created
    if [ -n "$SUBSCRIBER_ID" ]; then
        curl -s -X DELETE "$API_URL/subscribers/$SUBSCRIBER_ID" > /dev/null 2>&1 || true
        print_info "Test subscriber cleanup attempted"
    fi
}

# Main testing function
main() {
    echo "🧪 API Testing for Notification Service"
    echo "======================================="
    echo ""
    
    # Get API URL
    API_URL=$(get_api_url)
    
    if [ -z "$API_URL" ]; then
        print_fail "Could not get API URL. Make sure the service is deployed."
        echo "Run: cd terraform && terraform output api_gateway_url"
        exit 1
    fi
    
    print_info "Testing API at: $API_URL"
    echo ""
    
    # Initialize counters
    local total_tests=0
    local passed_tests=0
    
    # Run tests
    tests=(
        "test_health"
        "test_create_template"
        "test_get_template"
        "test_list_templates"
        "test_create_subscriber"
        "test_get_subscriber"
        "test_list_subscribers"
        "test_send_notification"
        "test_stats"
        "test_invalid_endpoints"
    )
    
    for test_func in "${tests[@]}"; do
        echo ""
        ((total_tests++))
        if $test_func; then
            ((passed_tests++))
        fi
        echo ""
    done
    
    # Cleanup
    cleanup_test_data
    
    # Summary
    echo "📊 Test Summary:"
    echo "================"
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $((total_tests - passed_tests))"
    
    if [ "$passed_tests" -eq "$total_tests" ]; then
        print_pass "All tests passed! 🎉"
        exit 0
    else
        print_fail "Some tests failed. Check the output above for details."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "health")
        API_URL=$(get_api_url)
        if [ -n "$API_URL" ]; then
            test_health
        else
            print_fail "Could not get API URL"
            exit 1
        fi
        ;;
    "quick")
        API_URL=$(get_api_url)
        if [ -n "$API_URL" ]; then
            test_health
            test_list_templates
            test_list_subscribers
            test_stats
        else
            print_fail "Could not get API URL"
            exit 1
        fi
        ;;
    *)
        main
        ;;
esac