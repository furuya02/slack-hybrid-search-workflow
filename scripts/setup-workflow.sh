#!/bin/bash
set -e

# ===========================================
# OpenSearch Serverless Workflow Setup Script
# ===========================================
# This script creates the hybrid search workflow using OpenSearch Flow Framework API.
# Run this AFTER CDK deployment.
#
# Prerequisites:
# - CDK stack deployed
# - AWS CLI configured
# - jq installed
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Configuration (override via environment variables or .env file)
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
COLLECTION_NAME="${COLLECTION_NAME:-slack-knowledge-base}"
INDEX_NAME="${INDEX_NAME:-slack-messages}"

echo "============================================="
echo "OpenSearch Serverless Workflow Setup"
echo "============================================="
echo "Region: $AWS_REGION"
echo "Collection: $COLLECTION_NAME"
echo "Index: $INDEX_NAME"
echo ""

# Get collection endpoint from CDK outputs or AWS CLI
echo "Fetching collection endpoint..."
COLLECTION_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name SlackHybridSearchStack \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='CollectionEndpoint'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -z "$COLLECTION_ENDPOINT" ]; then
    # Try to get from OpenSearch Serverless directly
    COLLECTION_ENDPOINT=$(aws opensearchserverless batch-get-collection \
        --names "$COLLECTION_NAME" \
        --region "$AWS_REGION" \
        --query "collectionDetails[0].collectionEndpoint" \
        --output text 2>/dev/null || echo "")
fi

if [ -z "$COLLECTION_ENDPOINT" ] || [ "$COLLECTION_ENDPOINT" == "None" ]; then
    echo "Error: Could not find collection endpoint."
    echo "Please ensure the CDK stack is deployed and the collection is created."
    exit 1
fi

echo "Collection Endpoint: $COLLECTION_ENDPOINT"

# Get OpenSearch Bedrock Role ARN
echo "Fetching Bedrock role ARN..."
BEDROCK_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name SlackHybridSearchStack \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='OpenSearchBedrockRoleArn'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -z "$BEDROCK_ROLE_ARN" ] || [ "$BEDROCK_ROLE_ARN" == "None" ]; then
    echo "Error: Could not find Bedrock role ARN."
    exit 1
fi

echo "Bedrock Role ARN: $BEDROCK_ROLE_ARN"
echo ""

# Generate AWS SigV4 signed request helper
sign_request() {
    local method=$1
    local path=$2
    local body=$3

    aws opensearchserverless api-call \
        --http-method "$method" \
        --api-path "$path" \
        --request-body "$body" \
        --region "$AWS_REGION" \
        2>&1
}

# Extract host from endpoint
OPENSEARCH_HOST=$(echo "$COLLECTION_ENDPOINT" | sed 's|https://||')

echo "============================================="
echo "Step 1: Create Bedrock Connector"
echo "============================================="

CONNECTOR_BODY=$(cat <<EOF
{
  "name": "Bedrock Titan Embeddings Connector",
  "description": "Connector for Amazon Bedrock Titan Embeddings V2",
  "version": 1,
  "protocol": "aws_sigv4",
  "credential": {
    "roleArn": "$BEDROCK_ROLE_ARN"
  },
  "parameters": {
    "region": "$AWS_REGION",
    "service_name": "bedrock",
    "model": "amazon.titan-embed-text-v2:0"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "https://bedrock-runtime.$AWS_REGION.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke",
      "headers": {
        "Content-Type": "application/json"
      },
      "request_body": "{ \"inputText\": \"\${parameters.inputText}\", \"dimensions\": 1024, \"normalize\": true }",
      "post_process_function": "connector.post_process.default.embedding"
    }
  ]
}
EOF
)

echo "Creating connector..."
echo "$CONNECTOR_BODY" > /tmp/connector.json

# Using curl with AWS SigV4
CONNECTOR_RESPONSE=$(curl -s -X POST \
    "$COLLECTION_ENDPOINT/_plugins/_ml/connectors/_create" \
    --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d @/tmp/connector.json 2>&1 || echo '{"error": "curl failed"}')

echo "Response: $CONNECTOR_RESPONSE"

CONNECTOR_ID=$(echo "$CONNECTOR_RESPONSE" | jq -r '.connector_id // empty')
if [ -z "$CONNECTOR_ID" ]; then
    echo "Warning: Could not extract connector_id. The connector may already exist."
    echo "Continuing with manual setup..."
fi

echo ""
echo "============================================="
echo "Step 2: Register and Deploy Model"
echo "============================================="

if [ -n "$CONNECTOR_ID" ]; then
    MODEL_BODY=$(cat <<EOF
{
  "name": "Titan Embeddings V2 Model",
  "function_name": "remote",
  "connector_id": "$CONNECTOR_ID"
}
EOF
)

    echo "Registering model..."
    MODEL_RESPONSE=$(curl -s -X POST \
        "$COLLECTION_ENDPOINT/_plugins/_ml/models/_register" \
        --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        -H "Content-Type: application/json" \
        -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
        -d "$MODEL_BODY" 2>&1 || echo '{"error": "curl failed"}')

    echo "Response: $MODEL_RESPONSE"

    MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.model_id // empty')

    if [ -n "$MODEL_ID" ]; then
        echo "Deploying model..."
        DEPLOY_RESPONSE=$(curl -s -X POST \
            "$COLLECTION_ENDPOINT/_plugins/_ml/models/$MODEL_ID/_deploy" \
            --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
            --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
            -H "Content-Type: application/json" \
            -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
            2>&1 || echo '{"error": "curl failed"}')

        echo "Deploy response: $DEPLOY_RESPONSE"
    fi
fi

echo ""
echo "============================================="
echo "Step 3: Create Ingest Pipeline"
echo "============================================="

MODEL_ID_TO_USE="${MODEL_ID:-YOUR_MODEL_ID}"

INGEST_PIPELINE_BODY=$(cat <<EOF
{
  "description": "Pipeline for embedding Slack messages",
  "processors": [
    {
      "text_embedding": {
        "model_id": "$MODEL_ID_TO_USE",
        "field_map": {
          "text": "text_embedding"
        }
      }
    }
  ]
}
EOF
)

echo "Creating ingest pipeline..."
PIPELINE_RESPONSE=$(curl -s -X PUT \
    "$COLLECTION_ENDPOINT/_ingest/pipeline/slack-ingest-pipeline" \
    --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d "$INGEST_PIPELINE_BODY" 2>&1 || echo '{"error": "curl failed"}')

echo "Response: $PIPELINE_RESPONSE"

echo ""
echo "============================================="
echo "Step 4: Create Index"
echo "============================================="

INDEX_BODY=$(cat <<EOF
{
  "settings": {
    "index": {
      "knn": true,
      "default_pipeline": "slack-ingest-pipeline"
    }
  },
  "mappings": {
    "properties": {
      "message_id": { "type": "keyword" },
      "channel_id": { "type": "keyword" },
      "user_id": { "type": "keyword" },
      "text": {
        "type": "text",
        "analyzer": "standard"
      },
      "text_embedding": {
        "type": "knn_vector",
        "dimension": 1024,
        "method": {
          "name": "hnsw",
          "engine": "faiss",
          "space_type": "l2",
          "parameters": {
            "ef_construction": 256,
            "m": 48
          }
        }
      },
      "timestamp": { "type": "keyword" },
      "thread_ts": { "type": "keyword" },
      "team_id": { "type": "keyword" },
      "event_time": { "type": "long" }
    }
  }
}
EOF
)

echo "Creating index..."
INDEX_RESPONSE=$(curl -s -X PUT \
    "$COLLECTION_ENDPOINT/$INDEX_NAME" \
    --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d "$INDEX_BODY" 2>&1 || echo '{"error": "curl failed"}')

echo "Response: $INDEX_RESPONSE"

echo ""
echo "============================================="
echo "Step 5: Create Search Pipeline"
echo "============================================="

SEARCH_PIPELINE_BODY=$(cat <<EOF
{
  "description": "Hybrid search pipeline with score normalization",
  "phase_results_processors": [
    {
      "normalization-processor": {
        "normalization": {
          "technique": "min_max"
        },
        "combination": {
          "technique": "arithmetic_mean",
          "parameters": {
            "weights": [0.3, 0.7]
          }
        }
      }
    }
  ]
}
EOF
)

echo "Creating search pipeline..."
SEARCH_PIPELINE_RESPONSE=$(curl -s -X PUT \
    "$COLLECTION_ENDPOINT/_search/pipeline/hybrid-search-pipeline" \
    --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d "$SEARCH_PIPELINE_BODY" 2>&1 || echo '{"error": "curl failed"}')

echo "Response: $SEARCH_PIPELINE_RESPONSE"

echo ""
echo "============================================="
echo "Setup Complete!"
echo "============================================="
echo ""
echo "Created resources:"
echo "  - Bedrock Connector: $CONNECTOR_ID"
echo "  - ML Model: $MODEL_ID"
echo "  - Ingest Pipeline: slack-ingest-pipeline"
echo "  - Index: $INDEX_NAME"
echo "  - Search Pipeline: hybrid-search-pipeline"
echo ""
echo "Next steps:"
echo "1. Configure Slack App with the webhook URL"
echo "2. Test the search API"
echo ""

# Save configuration for reference
cat > "$PROJECT_ROOT/.workflow-config.json" <<EOF
{
  "collection_endpoint": "$COLLECTION_ENDPOINT",
  "connector_id": "$CONNECTOR_ID",
  "model_id": "$MODEL_ID",
  "index_name": "$INDEX_NAME",
  "ingest_pipeline": "slack-ingest-pipeline",
  "search_pipeline": "hybrid-search-pipeline"
}
EOF

echo "Configuration saved to .workflow-config.json"
