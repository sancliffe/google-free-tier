#!/bin/bash
set -e

echo "Running Terraform validation tests..."

# Test 1: Validate syntax
terraform validate

# Test 2: Check formatting
terraform fmt -check -recursive

# Test 3: Plan with minimal config
terraform plan -var="enable_gke=false" -var="enable_cloud_run=false" -compact-warnings -no-color

echo "All tests passed!"
