#!/bin/bash

# ===========================================
# Cost Check Script
# ===========================================
# Check the current status and estimated costs for the deployment.
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
COLLECTION_NAME="${COLLECTION_NAME:-slack-knowledge-base}"

echo "============================================="
echo "Slack Hybrid Search - Cost Check"
echo "============================================="
echo ""

# Check if collection exists
echo "Checking OpenSearch Serverless Collection..."
COLLECTION_STATUS=$(aws opensearchserverless batch-get-collection \
    --names "$COLLECTION_NAME" \
    --region "$AWS_REGION" \
    --query "collectionDetails[0].status" \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$COLLECTION_STATUS" == "NOT_FOUND" ] || [ -z "$COLLECTION_STATUS" ]; then
    echo "  Status: NOT DEPLOYED"
    echo "  Cost: $0.00 (no resources)"
else
    echo "  Status: $COLLECTION_STATUS"

    # Get collection details
    COLLECTION_INFO=$(aws opensearchserverless batch-get-collection \
        --names "$COLLECTION_NAME" \
        --region "$AWS_REGION" \
        --query "collectionDetails[0]" \
        --output json 2>/dev/null)

    echo "  Collection Info:"
    echo "$COLLECTION_INFO" | jq -r '
        "    Name: \(.name)",
        "    Type: \(.type)",
        "    Endpoint: \(.collectionEndpoint)"
    '

    echo ""
    echo "  Estimated Cost (if running 24/7):"
    echo "    OpenSearch Serverless: ~$0.24/OCU-hour"
    echo "    - Indexing: 0.5 OCU minimum = ~$2.88/day"
    echo "    - Search:   0.5 OCU minimum = ~$2.88/day"
    echo "    - Total:    ~$5.76/day = ~$40.32/week"
    echo ""
    echo "    Bedrock (Titan Embeddings V2):"
    echo "    - ~$0.00002/1K input tokens"
    echo "    - Typical message (100 tokens): $0.000002"
    echo ""
    echo "    Lambda + API Gateway: Usually within free tier"
fi

echo ""
echo "============================================="
echo "Cost Optimization Tips"
echo "============================================="
echo ""
echo "1. DELETE when not testing:"
echo "   ./scripts/cleanup.sh"
echo ""
echo "2. OpenSearch Serverless has NO pause option"
echo "   You must delete the collection to stop charges"
echo ""
echo "3. Bedrock costs are minimal for small-scale testing"
echo ""
echo "4. For production, consider:"
echo "   - OpenSearch Ingestion for batch processing"
echo "   - Reserved capacity discounts"
echo ""
