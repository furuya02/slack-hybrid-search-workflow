# OpenSearch Workflow API（Flow Framework）について

## 概要

OpenSearch Workflow API は、**Flow Framework プラグイン**として OpenSearch 2.13 で導入された機能です。複雑なセットアップや前処理タスクを自動化し、**1回のAPI呼び出しで複雑な構成を完了**できるようにします。

## 主な特徴

- **ノーコード/ローコード体験**: ドラッグ&ドロップデザイナーでAI検索ワークフローを構築
- **自動化テンプレート**: コネクタ作成、モデル登録・デプロイ、パイプライン作成を一括実行
- **JSON/YAML対応**: ワークフロー定義をJSONまたはYAML形式で記述可能
- **依存関係の自動解決**: ノード間の依存関係を定義すると、適切な順序で実行

## ユースケース

| ユースケース | 説明 |
|-------------|------|
| RAG（検索拡張生成） | 生成AIと検索を組み合わせた回答生成 |
| ベクトル検索 | ML推論プロセッサを使った類似検索 |
| AI Connectors | 外部AIサービス（Amazon Bedrock等）との連携 |
| 会話型検索 | チャットベースの検索体験 |

## 主要なAPI

### 1. Create Workflow + Provision（本プロジェクトで使用）
```
POST /_plugins/_flow_framework/workflow?provision=true
```
ワークフローの作成とプロビジョニングを同時に実行。

### 2. Create/Update Workflow
```
POST /_plugins/_flow_framework/workflow
PUT /_plugins/_flow_framework/workflow/{workflow_id}
```
ワークフローの作成・更新を行う。

### 3. Provision Workflow
```
POST /_plugins/_flow_framework/workflow/{workflow_id}/_provision
```
定義したワークフローを実行（プロビジョニング）する。

### 4. Get Workflow Status
```
GET /_plugins/_flow_framework/workflow/{workflow_id}/_status
```
ワークフローの実行状態を確認する。

### 5. Deprovision Workflow
```
POST /_plugins/_flow_framework/workflow/{workflow_id}/_deprovision
```
プロビジョニングを解除し、リソースを削除する。

---

## 本プロジェクトでの Workflow 設定内容

本プロジェクト（Slack Hybrid Search）では、Workflow API を使用して以下の6つのリソースを一括作成します。

### 設定するリソース一覧

| No | リソース | ノードタイプ | 用途 |
|----|---------|-------------|------|
| 1 | AI Connector | `create_connector` | Bedrock との接続定義 |
| 2 | Model | `register_remote_model` | コネクタを使用するモデルの登録 |
| 3 | Model Deploy | `deploy_model` | モデルのデプロイ |
| 4 | Ingest Pipeline | `create_ingest_pipeline` | ドキュメント登録時のベクトル化 |
| 5 | Index | `create_index` | k-NN対応インデックス |
| 6 | Search Pipeline | `create_search_pipeline` | ハイブリッド検索のスコア正規化 |

### 依存関係

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

## Workflow テンプレート

本プロジェクトでは `scripts/workflow-template.json` でワークフローを定義しています。

### 完全なテンプレート

```json
{
  "name": "slack-hybrid-search",
  "workflows": {
    "provision": {
      "nodes": [
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
              "pre_process_function": "【カスタム Painless スクリプト - 詳細は AI_Connector_PreProcess.md 参照】",
              "post_process_function": "【カスタム Painless スクリプト - 詳細は AI_Connector_PreProcess.md 参照】"
            }]
          }
        },
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
        },
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
        },
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
        },
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
      ]
    }
  }
}
```

---

## 各ノードの詳細

### 1. create_connector（AI Connector）

Amazon Bedrock の Titan Embeddings V2 モデルに接続するためのコネクタを作成します。

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `protocol` | `aws_sigv4` | AWS SigV4認証を使用 |
| `credential.roleArn` | `OpenSearchBedrockRole` | Bedrock呼び出し用IAMロール |
| `parameters.model` | `amazon.titan-embed-text-v2:0` | 使用するBedrockモデル |
| `dimensions` | `1024` | 出力ベクトルの次元数 |
| `pre_process_function` | カスタム Painless スクリプト | Neural Search の入力を Bedrock 形式に変換 |
| `post_process_function` | カスタム Painless スクリプト | Bedrock のレスポンスを OpenSearch 形式に変換 |

> **重要**: Neural Search を使用する場合、カスタムの `pre_process_function` と `post_process_function` が**必須**です。詳細は [AI Connector の Pre/Post Process Function](./AI_Connector_PreProcess.md) を参照してください。

### 2. register_model / deploy_model（モデル登録・デプロイ）

コネクタを使用するリモートモデルを登録し、デプロイします。

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `function_name` | `remote` | 外部サービス（Bedrock）を使用 |
| `previous_node_inputs` | `create_connector: connector_id` | 前のノードからコネクタIDを受け取る |

### 3. create_ingest_pipeline（インジェストパイプライン）

ドキュメント登録時に `text` フィールドを自動的にベクトル化します。

| 設定 | 値 | 説明 |
|-----|-----|------|
| `pipeline_id` | `slack-ingest-pipeline` | パイプライン名 |
| `model_id` | `${{deploy_model.model_id}}` | デプロイされたモデルのIDを参照 |
| `field_map` | `text → text_embedding` | 入力→出力フィールドのマッピング |

> **Note**: `model_id` は `${{deploy_model.model_id}}` という構文で、前のノードで作成されたモデルIDを自動的に参照します。

### 4. create_index（k-NN対応インデックス）

ハイブリッド検索に対応したインデックスを作成します。

| 設定 | 値 | 説明 |
|-----|-----|------|
| `knn` | `true` | k-NN検索を有効化 |
| `default_pipeline` | `slack-ingest-pipeline` | 自動適用するパイプライン |
| `dimension` | `1024` | ベクトル次元数 |
| `method.engine` | `faiss` | Facebook AI Similarity Search |
| `space_type` | `l2` | ユークリッド距離 |

### 5. create_search_pipeline（検索パイプライン）

ハイブリッド検索時のスコア正規化・統合を行います。

| 設定 | 値 | 説明 |
|-----|-----|------|
| `pipeline_id` | `hybrid-search-pipeline` | パイプライン名 |
| `normalization.technique` | `min_max` | スコアを0〜1に正規化 |
| `combination.technique` | `arithmetic_mean` | 加重平均でスコア統合 |
| `weights` | `[0.3, 0.7]` | BM25: 30%, k-NN: 70% |

---

## 実行方法

### スクリプトによる実行

```bash
# .envにDOMAIN_ENDPOINT, BEDROCK_ROLE_ARN, AWS認証情報を設定後
./scripts/setup-workflow-api.sh
```

### 手動での実行

```bash
curl -s -X POST \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow?provision=true" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "Content-Type: application/json" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
    -d @workflow-template.json
```

### 実行結果の確認

```bash
# ステータス確認
curl -s -X GET \
    "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow/{workflow_id}/_status" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN"
```

---

## 重みの調整ガイド

検索結果の品質に応じて Search Pipeline の `weights` を調整できます。

| ユースケース | BM25 | k-NN | 設定 |
|-------------|------|------|------|
| 意味検索重視 | 0.2 | 0.8 | 同義語・言い換えに強い |
| **デフォルト** | **0.3** | **0.7** | バランス型 |
| キーワード重視 | 0.5 | 0.5 | 完全一致に強い |
| 完全一致重視 | 0.7 | 0.3 | 製品名・型番検索向け |

---

## 参考リンク

- [OpenSearch Flow Framework Documentation](https://docs.opensearch.org/latest/automating-configurations/api/provision-workflow/)
- [GitHub - opensearch-project/flow-framework](https://github.com/opensearch-project/flow-framework)
- [Amazon OpenSearch Service flow framework templates](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-workflow-framework.html)
