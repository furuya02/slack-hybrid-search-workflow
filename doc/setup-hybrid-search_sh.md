# setup-hybrid-search.sh 詳細解説（参考用）

## 概要

`setup-hybrid-search.sh` は、**個別のAPIを順番に呼び出してリソースを作成する方式**のスクリプトです。

> **推奨**: 本番環境では `setup-workflow-api.sh`（Workflow API 版）を使用してください。
> このスクリプトは、Workflow API を使わない場合の参考実装です。

### Workflow API 版との比較

| 項目 | setup-workflow-api.sh | setup-hybrid-search.sh |
|------|----------------------|------------------------|
| 使用するAPI | Flow Framework（Workflow API） | 個別の ML Commons / Pipeline API |
| API呼び出し回数 | **1回** | 5〜6回 |
| 依存関係の解決 | **自動**（previous_node_inputs で定義） | スクリプトで順番に実行 |
| リソース削除 | `_deprovision` で一括削除可能 | 個別に削除が必要 |

### スクリプトの位置づけ

```
┌─────────────────┐     ┌───────────────────────┐     ┌─────────────────┐
│   CDK Deploy    │────▶│  setup-hybrid-search  │────▶│   動作確認      │
│                 │     │         .sh           │     │                 │
│ - Domain        │     │ - AI Connector        │     │ - サンプルデータ │
│ - Lambda        │     │ - Model               │     │ - 検索テスト     │
│ - API Gateway   │     │ - Ingest Pipeline     │     │                 │
│ - IAM Role      │     │ - Index               │     │                 │
│                 │     │ - Search Pipeline     │     │                 │
└─────────────────┘     └───────────────────────┘     └─────────────────┘
```

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
./scripts/setup-hybrid-search.sh
```

---

## スクリプト構成

### 1. 初期化と設定読み込み

```bash
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
```

#### 環境変数

| 変数 | 必須 | デフォルト値 | 説明 |
|------|:----:|-------------|------|
| `DOMAIN_ENDPOINT` | ✅ | - | OpenSearch Service ドメインのエンドポイント |
| `BEDROCK_ROLE_ARN` | ✅ | - | OpenSearchがBedrockを呼び出すためのIAMロールARN |
| `AWS_REGION` | - | `ap-northeast-1` | AWSリージョン |
| `INDEX_NAME` | - | `slack-messages` | 作成するインデックス名 |

---

### 2. API呼び出しヘルパー関数

```bash
call_api() {
    curl -s -X "$1" "https://${DOMAIN_ENDPOINT}$2" \
        --aws-sigv4 "aws:amz:$AWS_REGION:es" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        -H "Content-Type: application/json" \
        -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
        -d "$3"
}
```

OpenSearch Service への API リクエストを AWS SigV4 署名付きで送信する共通関数です。

#### 引数

| 引数 | 説明 | 例 |
|------|------|-----|
| `$1` (method) | HTTPメソッド | `POST`, `PUT`, `GET`, `DELETE` |
| `$2` (path) | APIパス | `/_plugins/_ml/connectors/_create` |
| `$3` (body) | リクエストボディ（JSON） | `'{"name": "test"}'` |

#### curl オプションの説明

| オプション | 値 | 説明 |
|-----------|-----|------|
| `-s` | - | サイレントモード（進捗表示を抑制） |
| `-X "$1"` | `POST`, `PUT` など | HTTPメソッドを指定 |
| `--aws-sigv4` | `aws:amz:$AWS_REGION:es` | AWS SigV4署名を有効化。`es` は OpenSearch Service のサービス名 |
| `--user` | `$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY` | 認証情報を指定 |
| `-H "Content-Type: ..."` | `application/json` | リクエストヘッダー |
| `-H "x-amz-security-token: ..."` | `$AWS_SESSION_TOKEN` | 一時認証情報のセッショントークン |
| `-d "$3"` | JSON文字列 | リクエストボディ |

---

### 3. Step 1: AI Connector の作成

```bash
echo "=== Step 1: Create Connector ==="
CONNECTOR_ID=$(call_api POST "/_plugins/_ml/connectors/_create" '{
  "name": "Bedrock Titan Connector",
  "description": "Connector for Amazon Bedrock Titan Embeddings V2",
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
```

#### API エンドポイント

```
POST /_plugins/_ml/connectors/_create
```

#### 主要フィールド

| フィールド | 値 | 説明 |
|-----------|-----|------|
| `protocol` | `aws_sigv4` | AWS署名v4認証を使用 |
| `credential.roleArn` | `.env`から取得 | OpenSearchがBedrockを呼び出す際のIAMロール |
| `parameters.model` | `amazon.titan-embed-text-v2:0` | 使用するBedrock埋め込みモデル |
| `dimensions` | `1024` | 出力ベクトルの次元数 |
| `post_process_function` | `connector.post_process.default.embedding` | Bedrockレスポンスからベクトルを抽出 |

---

### 4. Step 2: モデルの登録とデプロイ

```bash
echo "=== Step 2: Register & Deploy Model ==="
MODEL_ID=$(call_api POST "/_plugins/_ml/models/_register" '{
  "name": "Titan Embeddings V2",
  "function_name": "remote",
  "connector_id": "'"$CONNECTOR_ID"'"
}' | jq -r '.model_id')
echo "Model ID: $MODEL_ID"

call_api POST "/_plugins/_ml/models/$MODEL_ID/_deploy" "{}" | jq .
```

#### API エンドポイント

| 操作 | エンドポイント |
|------|---------------|
| 登録 | `POST /_plugins/_ml/models/_register` |
| デプロイ | `POST /_plugins/_ml/models/{model_id}/_deploy` |

#### `_deploy` の動作（リモートモデルの場合）

```
┌─────────────────────────────────────────────────────────┐
│  OpenSearch ML Registry                                  │
│  ┌──────────────────────────────────────────────────┐   │
│  │  model_id: "abc123"                              │   │
│  │  function_name: "remote"                         │   │
│  │  connector_id: "xyz789"  ─────────────────────────┼───┼──▶ Bedrock
│  │  status: "DEPLOYED" ✓                            │   │     (実際のモデル)
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**重要**: リモートモデルの場合、`_deploy` はモデル自体をOpenSearchにロードするのではなく、**モデル登録をアクティブ状態にする**だけです。実際の埋め込み処理はBedrockで実行されます。

---

### 5. Step 3: インジェストパイプラインの作成

```bash
echo "=== Step 3: Create Ingest Pipeline ==="
call_api PUT "/_ingest/pipeline/slack-ingest-pipeline" '{
  "processors": [{ "text_embedding": { "model_id": "'"$MODEL_ID"'", "field_map": { "text": "text_embedding" } } }]
}' | jq .
```

#### API エンドポイント

```
PUT /_ingest/pipeline/slack-ingest-pipeline
```

#### 処理フロー

```
ドキュメント投入
    │
    ▼
{ "text": "今日の会議は15時からです" }
    │
    ▼ [text_embedding プロセッサ]
    │   └── model_id で指定されたモデル（Bedrock経由）でベクトル化
    ▼
{
  "text": "今日の会議は15時からです",
  "text_embedding": [0.123, 0.456, ..., 0.789]  // 1024次元
}
    │
    ▼
インデックスに保存
```

---

### 6. Step 4: インデックスの作成

```bash
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
```

#### API エンドポイント

```
PUT /slack-messages
```

#### フィールド定義

| フィールド | 型 | 用途 |
|-----------|-----|------|
| `message_id` | `keyword` | Slackメッセージの一意識別子 |
| `channel_id` | `keyword` | チャンネルID（フィルタリング用） |
| `user_id` | `keyword` | 投稿者ID（フィルタリング用） |
| `text` | `text` | メッセージ本文（BM25キーワード検索対象） |
| `text_embedding` | `knn_vector` | ベクトル（k-NN検索対象） |
| `timestamp` | `keyword` | 投稿時刻 |
| `thread_ts` | `keyword` | スレッドタイムスタンプ |
| `team_id` | `keyword` | ワークスペースID |
| `event_time` | `long` | UNIXタイムスタンプ |

#### k-NN設定

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| `method.name` | `hnsw` | Hierarchical Navigable Small World（近似最近傍探索） |
| `method.engine` | `faiss` | Facebook AI Similarity Search |
| `space_type` | `l2` | ユークリッド距離 |

---

### 7. Step 5: 検索パイプラインの作成

```bash
echo "=== Step 5: Create Search Pipeline ==="
call_api PUT "/_search/pipeline/hybrid-search-pipeline" '{
  "phase_results_processors": [{ "normalization-processor": {
    "normalization": { "technique": "min_max" },
    "combination": { "technique": "arithmetic_mean", "parameters": { "weights": [0.3, 0.7] } }
  }}]
}' | jq .
```

#### API エンドポイント

```
PUT /_search/pipeline/hybrid-search-pipeline
```

#### ハイブリッド検索のスコア計算

```
検索クエリ: "会議の議事録"
    │
    ├── BM25検索（キーワード）
    │   └── スコア: 2.5
    │
    └── k-NN検索（ベクトル）
        └── スコア: 0.85
    │
    ▼ [normalization-processor]
    │
    ├── min_max正規化
    │   ├── BM25: 2.5 → 0.8（0-1に正規化）
    │   └── k-NN: 0.85 → 0.6（0-1に正規化）
    │
    └── arithmetic_mean統合
        └── 最終スコア = 0.8 × 0.3 + 0.6 × 0.7 = 0.66
```

#### 重み設定ガイド

| ユースケース | BM25 | k-NN | 設定値 |
|-------------|------|------|--------|
| 意味検索重視 | 0.2 | 0.8 | 同義語・言い換えに強い |
| **デフォルト** | **0.3** | **0.7** | バランス型 |
| キーワード重視 | 0.5 | 0.5 | 完全一致に強い |
| 完全一致重視 | 0.7 | 0.3 | 製品名・型番検索向け |

---

### 8. 完了メッセージ

```bash
echo "=== Done ==="
echo "Connector: $CONNECTOR_ID"
echo "Model: $MODEL_ID"
```

スクリプト実行後、作成された Connector ID と Model ID が表示されます。

---

## 出力例

```
=== Step 1: Create Connector ===
Connector ID: conn_abc123xyz

=== Step 2: Register & Deploy Model ===
Model ID: model_xyz789abc
{
  "task_id": "task_123",
  "status": "CREATED"
}

=== Step 3: Create Ingest Pipeline ===
{
  "acknowledged": true
}

=== Step 4: Create Index ===
{
  "acknowledged": true,
  "shards_acknowledged": true,
  "index": "slack-messages"
}

=== Step 5: Create Search Pipeline ===
{
  "acknowledged": true
}

=== Done ===
Connector: conn_abc123xyz
Model: model_xyz789abc
```

---

## リソースの削除

Workflow API と異なり、個別に削除する必要があります。

### 削除順序（依存関係の逆順）

```bash
# 1. インデックスを削除
call_api DELETE "/slack-messages" ""

# 2. 検索パイプラインを削除
call_api DELETE "/_search/pipeline/hybrid-search-pipeline" ""

# 3. インジェストパイプラインを削除
call_api DELETE "/_ingest/pipeline/slack-ingest-pipeline" ""

# 4. モデルをアンデプロイ・削除
call_api POST "/_plugins/_ml/models/{model_id}/_undeploy" "{}"
call_api DELETE "/_plugins/_ml/models/{model_id}" ""

# 5. コネクタを削除
call_api DELETE "/_plugins/_ml/connectors/{connector_id}" ""
```

---

## エラーハンドリング

### よくあるエラーと対処法

| エラー | 原因 | 対処法 |
|-------|------|--------|
| `DOMAIN_ENDPOINT is required` | `.env` に設定がない | CDK出力からエンドポイントを取得して設定 |
| `BEDROCK_ROLE_ARN is required` | `.env` に設定がない | CDK出力からロールARNを取得して設定 |
| `curl: (6) Could not resolve host` | エンドポイントが無効 | ドメインの状態を確認 |
| `{"error": "security_exception"}` | 認証エラー | AWS認証情報を確認 |
| `connector_id is null` | Connector作成失敗 | エラーメッセージを確認、IAMロール設定を確認 |

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `scripts/setup-workflow-api.sh` | Workflow API版（推奨） |
| `scripts/workflow-template.json` | Workflow定義テンプレート |
| `.env` | 環境変数設定ファイル |
| `scripts/load-sample-data.sh` | サンプルデータ投入スクリプト |

---

## 参考

- [OpenSearch ML Commons - Connectors](https://opensearch.org/docs/latest/ml-commons-plugin/remote-models/connectors/)
- [OpenSearch Ingest Pipelines](https://opensearch.org/docs/latest/ingest-pipelines/)
- [OpenSearch k-NN Plugin](https://opensearch.org/docs/latest/search-plugins/knn/index/)
- [OpenSearch Search Pipelines](https://opensearch.org/docs/latest/search-plugins/search-pipelines/index/)
