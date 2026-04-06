# setup-workflow-api.sh 詳細解説

## 概要

`setup-workflow-api.sh` は、**OpenSearch Flow Framework（Workflow API）を使用して、1回のAPI呼び出しで全リソースを一括作成**するスクリプトです。

### 個別API方式との比較

| 項目 | setup-workflow-api.sh | setup-hybrid-search.sh |
|------|----------------------|------------------------|
| 使用するAPI | Flow Framework（Workflow API） | 個別の ML Commons / Pipeline API |
| API呼び出し回数 | **1回** | 5〜6回 |
| 依存関係の解決 | **自動**（previous_node_inputs で定義） | スクリプトで順番に実行 |
| リソース削除 | `_deprovision` で一括削除可能 | 個別に削除が必要 |

---

## 前提条件

| 項目 | 説明 |
|------|------|
| CDKスタック | `SlackHybridSearchStack` がデプロイ済み |
| `.env` ファイル | `DOMAIN_ENDPOINT` と `BEDROCK_ROLE_ARN` を設定 |
| AWS認証情報 | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` が環境変数に設定済み |
| jq | JSONパース用（`brew install jq`） |

---

## 実行方法

```bash
cd /path/to/slack-hybrid-search-workflow
./scripts/setup-workflow-api.sh
```

---

## スクリプト構成

```bash
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
```

### ポイント

| 項目 | 説明 |
|------|------|
| `?provision=true` | ワークフロー作成と同時にプロビジョニング（リソース作成）を実行 |
| `--aws-sigv4 "aws:amz:$AWS_REGION:es"` | OpenSearch Service 用の SigV4 認証（サービス名: `es`） |
| テンプレート置換 | `workflow-template.json` の `${BEDROCK_ROLE_ARN}` と `${AWS_REGION}` を環境変数で置換 |

---

## workflow-template.json の構造

### 全体構造

```json
{
  "name": "slack-hybrid-search",
  "workflows": {
    "provision": {
      "nodes": [ ... ]
    }
  }
}
```

### ノード（nodes）

ワークフローで作成するリソースを定義します。

| ノードID | type | 説明 |
|---------|------|------|
| `create_connector` | `create_connector` | Bedrock AI Connector を作成 |
| `register_model` | `register_remote_model` | リモートモデルを登録 |
| `deploy_model` | `deploy_model` | モデルをデプロイ（有効化） |
| `create_ingest_pipeline` | `create_ingest_pipeline` | インジェストパイプラインを作成 |
| `create_index` | `create_index` | k-NN対応インデックスを作成 |
| `create_search_pipeline` | `create_search_pipeline` | 検索パイプラインを作成 |

### previous_node_inputs - 依存関係と値の自動引き渡し

```json
{
  "id": "register_model",
  "type": "register_remote_model",
  "user_inputs": { ... },
  "previous_node_inputs": {
    "create_connector": "connector_id"
  }
}
```

`previous_node_inputs` により、前のノードで作成されたリソースのIDが自動的に次のノードに渡されます。

### 依存関係の流れ

```
create_connector
       ↓ connector_id
register_model
       ↓ model_id
deploy_model
       ↓ model_id
create_ingest_pipeline
       ↓ pipeline_id
create_index
       ↓ index_name
create_search_pipeline
```

---

## 主要なノード定義

### 1. create_connector

```json
{
  "id": "create_connector",
  "type": "create_connector",
  "user_inputs": {
    "name": "Bedrock Titan Connector",
    "description": "Connector for Amazon Bedrock Titan Embeddings V2",
    "version": "1",
    "protocol": "aws_sigv4",
    "credential": { "roleArn": "${BEDROCK_ROLE_ARN}" },
    "parameters": {
      "region": "${AWS_REGION}",
      "service_name": "bedrock",
      "model": "amazon.titan-embed-text-v2:0"
    },
    "actions": [{
      "action_type": "predict",
      "method": "POST",
      "url": "https://bedrock-runtime.${AWS_REGION}.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke",
      "request_body": "{ \"inputText\": \"${parameters.inputText}\", \"dimensions\": 1024, \"normalize\": true }",
      "pre_process_function": "【カスタム Painless スクリプト】",
      "post_process_function": "【カスタム Painless スクリプト】"
    }]
  }
}
```

> **重要**: Neural Search を使用する場合、カスタムの `pre_process_function` と `post_process_function` が**必須**です。詳細は [AI Connector の Pre/Post Process Function](./AI_Connector_PreProcess.md) を参照してください。

### 2. register_model / deploy_model

```json
{
  "id": "register_model",
  "type": "register_remote_model",
  "user_inputs": { "name": "Titan Embeddings V2", "function_name": "remote" },
  "previous_node_inputs": { "create_connector": "connector_id" }
},
{
  "id": "deploy_model",
  "type": "deploy_model",
  "previous_node_inputs": { "register_model": "model_id" }
}
```

### 3. create_ingest_pipeline

```json
{
  "id": "create_ingest_pipeline",
  "type": "create_ingest_pipeline",
  "user_inputs": {
    "pipeline_id": "slack-ingest-pipeline",
    "configurations": {
      "processors": [{ "text_embedding": { "model_id": "${{deploy_model.model_id}}", "field_map": { "text": "text_embedding" } } }]
    }
  },
  "previous_node_inputs": { "deploy_model": "model_id" }
}
```

`model_id` は `${{deploy_model.model_id}}` という構文で、`deploy_model` ノードで作成されたモデルIDを自動的に参照します。

### 4. create_index

```json
{
  "id": "create_index",
  "type": "create_index",
  "user_inputs": {
    "index_name": "slack-messages",
    "configurations": {
      "settings": { "index": { "knn": true, "default_pipeline": "slack-ingest-pipeline" } },
      "mappings": { "properties": {
        "message_id": { "type": "keyword" },
        "channel_id": { "type": "keyword" },
        "user_id": { "type": "keyword" },
        "text": { "type": "text" },
        "text_embedding": {
          "type": "knn_vector",
          "dimension": 1024,
          "method": { "name": "hnsw", "engine": "faiss", "space_type": "l2" }
        },
        "timestamp": { "type": "keyword" },
        "thread_ts": { "type": "keyword" },
        "team_id": { "type": "keyword" },
        "event_time": { "type": "long" }
      }}
    }
  },
  "previous_node_inputs": { "create_ingest_pipeline": "pipeline_id" }
}
```

### 5. create_search_pipeline

```json
{
  "id": "create_search_pipeline",
  "type": "create_search_pipeline",
  "user_inputs": {
    "pipeline_id": "hybrid-search-pipeline",
    "configurations": {
      "phase_results_processors": [{
        "normalization-processor": {
          "normalization": { "technique": "min_max" },
          "combination": { "technique": "arithmetic_mean", "parameters": { "weights": [0.3, 0.7] } }
        }
      }]
    }
  },
  "previous_node_inputs": { "create_index": "index_name" }
}
```

---

## 出力例

```
Endpoint: search-slack-hybrid-search-xxxxx.ap-northeast-1.es.amazonaws.com
Role ARN: arn:aws:iam::123456789012:role/OpenSearchBedrockRole

=== Creating and Provisioning Workflow ===
{
  "workflow_id": "dv_zYZ0BS3ey_-URlTo8"
}

Done! Check status with:
  GET /_plugins/_flow_framework/workflow/{workflow_id}/_status
```

---

## ワークフローの管理

### ステータス確認

```bash
curl -s -X GET \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow/{workflow_id}/_status" \
    --aws-sigv4 "aws:amz:$AWS_REGION:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" | jq .
```

レスポンス例：
```json
{
  "workflow_id": "dv_zYZ0BS3ey_-URlTo8",
  "state": "COMPLETED",
  "resources_created": [
    { "workflow_step_name": "create_connector", "resource_id": "conn_xxx" },
    { "workflow_step_name": "register_model", "resource_id": "model_xxx" },
    ...
  ]
}
```

### リソースの一括削除（Deprovision）

```bash
curl -s -X POST \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow/{workflow_id}/_deprovision" \
    --aws-sigv4 "aws:amz:$AWS_REGION:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" | jq .
```

ワークフローで作成された全リソースが削除されます。

### ワークフロー自体の削除

```bash
curl -s -X DELETE \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow/{workflow_id}" \
    --aws-sigv4 "aws:amz:$AWS_REGION:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" | jq .
```

---

## Workflow API の利点

1. **1回のAPI呼び出し**: 6つのリソースを1回のAPIで作成
2. **依存関係の自動解決**: `connector_id` → `model_id` の引き渡しが自動
3. **一括削除**: `_deprovision` で全リソースをまとめて削除
4. **状態管理**: ワークフローの状態（PROVISIONING, COMPLETED, FAILED）を追跡可能
5. **再現性**: テンプレートで設定を管理、異なる環境に簡単に適用

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `scripts/workflow-template.json` | ワークフロー定義テンプレート |
| `.env` | 環境変数設定ファイル |
| `scripts/setup-hybrid-search.sh` | 個別API版（参考用） |

---

## 参考

- [OpenSearch Flow Framework Documentation](https://opensearch.org/docs/latest/automating-configurations/workflow-templates/)
- [Create Workflow API](https://opensearch.org/docs/latest/automating-configurations/api/create-workflow/)
- [Provision Workflow API](https://opensearch.org/docs/latest/automating-configurations/api/provision-workflow/)
