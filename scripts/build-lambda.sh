#!/bin/bash

# Lambda Build Script for Notification Service
# This script builds the Lambda deployment package

set -e

echo "🔨 Building Lambda deployment package..."

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
SRC_DIR="$PROJECT_ROOT/src"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[BUILD]${NC} $1"
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

# Check if Node.js is installed
check_nodejs() {
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18.x or later."
        exit 1
    fi

    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_error "Node.js version must be 18 or later. Current version: $(node --version)"
        exit 1
    fi

    print_status "Node.js version: $(node --version) ✅"
}

# Clean build directory
clean_build() {
    print_status "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    print_status "Build directory cleaned ✅"
}

# Copy source files
copy_source() {
    print_status "Copying source files..."
    
    # Copy source code
    cp -r "$SRC_DIR" "$BUILD_DIR/"
    
    # Copy package.json and package-lock.json
    cp "$PROJECT_ROOT/package.json" "$BUILD_DIR/"
    if [ -f "$PROJECT_ROOT/package-lock.json" ]; then
        cp "$PROJECT_ROOT/package-lock.json" "$BUILD_DIR/"
    fi
    
    # Copy yarn.lock if it exists
    if [ -f "$PROJECT_ROOT/yarn.lock" ]; then
        cp "$PROJECT_ROOT/yarn.lock" "$BUILD_DIR/"
    fi
    
    print_status "Source files copied ✅"
}

# Install production dependencies
install_dependencies() {
    print_status "Installing production dependencies..."
    
    cd "$BUILD_DIR"
    
    # Install dependencies
    if [ -f "yarn.lock" ]; then
        print_info "Using Yarn to install dependencies..."
        yarn install --production --frozen-lockfile --no-optional
    elif [ -f "package-lock.json" ]; then
        print_info "Using npm to install dependencies..."
        npm ci --only=production --no-optional
    else
        print_info "Using npm to install dependencies..."
        npm install --only=production --no-optional
    fi
    
    cd "$PROJECT_ROOT"
    print_status "Dependencies installed ✅"
}

# Remove unnecessary files
cleanup_package() {
    print_status "Cleaning up package..."
    
    cd "$BUILD_DIR"
    
    # Remove development files
    find . -name "*.test.js" -delete
    find . -name "*.spec.js" -delete
    find . -name "__tests__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "coverage" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name ".nyc_output" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove documentation files from node_modules
    find node_modules -name "*.md" -delete 2>/dev/null || true
    find node_modules -name "*.txt" -delete 2>/dev/null || true
    find node_modules -name "LICENSE*" -delete 2>/dev/null || true
    find node_modules -name "CHANGELOG*" -delete 2>/dev/null || true
    find node_modules -name "README*" -delete 2>/dev/null || true
    
    # Remove .git directories
    find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name ".github" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove cache directories
    find node_modules -name ".cache" -type d -exec rm -rf {} + 2>/dev/null || true
    find node_modules -name "test" -type d -exec rm -rf {} + 2>/dev/null || true
    find node_modules -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true
    find node_modules -name "example" -type d -exec rm -rf {} + 2>/dev/null || true
    find node_modules -name "examples" -type d -exec rm -rf {} + 2>/dev/null || true
    
    cd "$PROJECT_ROOT"
    print_status "Package cleaned up ✅"
}

# Validate the build
validate_build() {
    print_status "Validating build..."
    
    # Check if required files exist
    required_files=(
        "$BUILD_DIR/src/handlers/api-handler.js"
        "$BUILD_DIR/src/handlers/stream-processor.js"
        "$BUILD_DIR/src/handlers/dlq-processor.js"
        "$BUILD_DIR/package.json"
        "$BUILD_DIR/node_modules"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -e "$file" ]; then
            print_error "Required file/directory not found: $file"
            exit 1
        fi
    done
    
    # Check package.json syntax
    if ! node -e "JSON.parse(require('fs').readFileSync('$BUILD_DIR/package.json', 'utf8'))"; then
        print_error "Invalid package.json syntax"
        exit 1
    fi
    
    # Check handler files syntax
    cd "$BUILD_DIR"
    for handler in src/handlers/*.js; do
        if ! node -c "$handler"; then
            print_error "Syntax error in $handler"
            exit 1
        fi
    done
    cd "$PROJECT_ROOT"
    
    print_status "Build validation passed ✅"
}

# Calculate package size
calculate_size() {
    print_status "Calculating package size..."
    
    if command -v du &> /dev/null; then
        SIZE=$(du -sh "$BUILD_DIR" | cut -f1)
        print_info "Build directory size: $SIZE"
        
        # Check if size exceeds Lambda limits
        SIZE_BYTES=$(du -s "$BUILD_DIR" | cut -f1)
        SIZE_MB=$((SIZE_BYTES / 1024))
        
        if [ "$SIZE_MB" -gt 250 ]; then
            print_warning "Package size ($SIZE_MB MB) exceeds AWS Lambda limit (250 MB unzipped)"
        elif [ "$SIZE_MB" -gt 50 ]; then
            print_warning "Package size ($SIZE_MB MB) is large. Consider optimizing."
        else
            print_status "Package size is optimal: $SIZE"
        fi
    fi
}

# Main build process
main() {
    print_info "🚀 Starting Lambda build process for Notification Service"
    print_info "================================================"
    
    check_nodejs
    clean_build
    copy_source
    install_dependencies
    cleanup_package
    validate_build
    calculate_size
    
    print_status "🎉 Lambda build completed successfully!"
    print_info "Build location: $BUILD_DIR"
    print_info "Ready for Terraform deployment"
}

# Handle script arguments
case "${1:-}" in
    "clean")
        print_status "Cleaning build directory only..."
        clean_build
        ;;
    "validate")
        if [ -d "$BUILD_DIR" ]; then
            validate_build
        else
            print_error "Build directory not found. Run build first."
            exit 1
        fi
        ;;
    "size")
        if [ -d "$BUILD_DIR" ]; then
            calculate_size
        else
            print_error "Build directory not found. Run build first."
            exit 1
        fi
        ;;
    *)
        main
        ;;
esac