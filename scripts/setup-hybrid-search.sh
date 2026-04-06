#!/bin/bash
# ===========================================
# 個別APIを使用したセットアップ（参考用）
# Workflow API を使わず、各APIを順番に呼び出す方式
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

set -a && source "$PROJECT_ROOT/.env" && set +a

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
INDEX_NAME="${INDEX_NAME:-slack-messages}"

# API呼び出し用関数
call_api() {
    curl -s -X "$1" "${COLLECTION_ENDPOINT}$2" \
        --aws-sigv4 "aws:amz:$AWS_REGION:aoss" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        -H "Content-Type: application/json" \
        -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
        -d "$3"
}

echo "=== Step 1: Create Connector ==="
CONNECTOR_ID=$(call_api POST "/_plugins/_ml/connectors/_create" '{
  "name": "Bedrock Titan Connector",
  "version": 1,
  "protocol": "aws_sigv4",
  "credential": { "roleArn": "'"$BEDROCK_ROLE_ARN"'" },
  "parameters": { "region": "'"$AWS_REGION"'", "service_name": "bedrock", "model": "amazon.titan-embed-text-v2:0" },
  "actions": [{
    "action_type": "predict",
    "method": "POST",
    "url": "https://bedrock-runtime.'"$AWS_REGION"'.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke",
    "headers": { "Content-Type": "application/json" },
    "request_body": "{ \"inputText\": \"${parameters.inputText}\", \"dimensions\": 1024, \"normalize\": true }",
    "post_process_function": "connector.post_process.default.embedding"
  }]
}' | jq -r '.connector_id')
echo "Connector ID: $CONNECTOR_ID"

echo ""
echo "=== Step 2: Register & Deploy Model ==="
MODEL_ID=$(call_api POST "/_plugins/_ml/models/_register" '{
  "name": "Titan Embeddings V2",
  "function_name": "remote",
  "connector_id": "'"$CONNECTOR_ID"'"
}' | jq -r '.model_id')
echo "Model ID: $MODEL_ID"

call_api POST "/_plugins/_ml/models/$MODEL_ID/_deploy" "{}" | jq .

echo ""
echo "=== Step 3: Create Ingest Pipeline ==="
call_api PUT "/_ingest/pipeline/slack-ingest-pipeline" '{
  "processors": [{ "text_embedding": { "model_id": "'"$MODEL_ID"'", "field_map": { "text": "text_embedding" } } }]
}' | jq .

echo ""
echo "=== Step 4: Create Index ==="
call_api PUT "/$INDEX_NAME" '{
  "settings": { "index": { "knn": true, "default_pipeline": "slack-ingest-pipeline" } },
  "mappings": { "properties": {
    "message_id": { "type": "keyword" },
    "channel_id": { "type": "keyword" },
    "user_id": { "type": "keyword" },
    "text": { "type": "text" },
    "text_embedding": { "type": "knn_vector", "dimension": 1024, "method": { "name": "hnsw", "engine": "faiss", "space_type": "l2" } },
    "timestamp": { "type": "keyword" },
    "thread_ts": { "type": "keyword" },
    "team_id": { "type": "keyword" },
    "event_time": { "type": "long" }
  }}
}' | jq .

echo ""
echo "=== Step 5: Create Search Pipeline ==="
call_api PUT "/_search/pipeline/hybrid-search-pipeline" '{
  "phase_results_processors": [{ "normalization-processor": {
    "normalization": { "technique": "min_max" },
    "combination": { "technique": "arithmetic_mean", "parameters": { "weights": [0.3, 0.7] } }
  }}]
}' | jq .

echo ""
echo "=== Done ==="
echo "Connector: $CONNECTOR_ID"
echo "Model: $MODEL_ID"
