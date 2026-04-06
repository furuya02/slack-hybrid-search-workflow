#!/bin/bash
# ===========================================
# OpenSearch Flow Framework (Workflow API) を使用したセットアップ
# 1回のAPI呼び出しで全リソースを一括作成
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# .env 読み込み
set -a && source "$PROJECT_ROOT/.env" && set +a

AWS_REGION="${AWS_REGION:-ap-northeast-1}"

echo "Endpoint: $DOMAIN_ENDPOINT"
echo "Role ARN: $BEDROCK_ROLE_ARN"
echo ""

# テンプレートの変数を置換
WORKFLOW_JSON=$(cat "$SCRIPT_DIR/workflow-template.json" | \
    sed "s|\${BEDROCK_ROLE_ARN}|$BEDROCK_ROLE_ARN|g" | \
    sed "s|\${AWS_REGION}|$AWS_REGION|g")

# Workflow を作成 & プロビジョニング（1回のAPI呼び出し）
echo "=== Creating and Provisioning Workflow ==="
curl -s -X POST \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow?provision=true" \
    --aws-sigv4 "aws:amz:$AWS_REGION:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d "$WORKFLOW_JSON" | jq .

echo ""
echo "Done! Check status with:"
echo "  GET /_plugins/_flow_framework/workflow/{workflow_id}/_status"
