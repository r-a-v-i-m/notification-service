# Data sources for existing AWS resources and account information

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Archive file for Lambda deployment package
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "../build"
  output_path = "../${var.project_name}.zip"
  
  depends_on = [null_resource.build_lambda_package]
}

# Lambda package build resource
resource "null_resource" "build_lambda_package" {
  triggers = {
    # Rebuild when source files change
    src_hash = data.archive_file.lambda_source_hash.output_base64sha256
  }

  provisioner "local-exec" {
    command = "../scripts/build-lambda.sh"
    working_dir = path.module
  }
}

# Hash of source files to detect changes
data "archive_file" "lambda_source_hash" {
  type        = "zip"
  source_dir  = "../src"
  output_path = "/tmp/${var.project_name}-src-hash.zip"
  excludes    = [
    "**/*.test.js",
    "**/node_modules/**",
    "**/.git/**",
    "**/coverage/**"
  ]
}