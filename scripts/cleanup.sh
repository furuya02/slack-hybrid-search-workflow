#!/bin/bash
set -e

# ===========================================
# Cleanup Script for Slack Hybrid Search
# ===========================================
# This script destroys all resources to stop AWS charges.
#
# WARNING: This will delete all data and cannot be undone!
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

AWS_REGION="${AWS_REGION:-ap-northeast-1}"

echo "============================================="
echo "Slack Hybrid Search Cleanup"
echo "============================================="
echo ""
echo "WARNING: This will DELETE all resources including:"
echo "  - OpenSearch Serverless Collection"
echo "  - Lambda Functions"
echo "  - API Gateway"
echo "  - All indexed data"
echo ""
echo "This action cannot be undone!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."

# Destroy CDK stack
echo "Destroying CDK stack..."
cd "$PROJECT_ROOT/cdk"
pnpm cdk destroy --force

echo ""
echo "============================================="
echo "Cleanup Complete!"
echo "============================================="
echo ""
echo "All resources have been deleted."
echo "No further AWS charges will be incurred for this project."
