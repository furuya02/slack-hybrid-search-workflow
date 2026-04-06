# Lambda関数

このドキュメントでは、Slack Hybrid Search システムで使用する2つのLambda関数について説明します。

## 概要

| 関数名 | 用途 |
|-------|------|
| `SlackHybridSearch-SlackWebhook` | Slackからのイベントを受信し、メッセージをOpenSearch Serviceにインデックス |
| `SlackHybridSearch-Search` | ハイブリッド検索（キーワード + ベクトル）を実行 |

---

## 1. SlackHybridSearch-SlackWebhook

Slackワークスペースで発生したメッセージイベントを受信し、OpenSearch Serviceにインデックスする関数です。

### 処理フロー

```
Slack Event → API Gateway → Lambda → OpenSearch Service
                              ↓
                    インジェストパイプライン
                    （Titan Embeddingsでベクトル化）
```

### 主要機能

| 機能 | 説明 |
|-----|------|
| **URL検証** | Slack Appの初期設定時に送信される`url_verification`チャレンジに応答 |
| **署名検証** | `X-Slack-Signature`ヘッダーを使用してリクエストがSlackからのものであることを検証 |
| **メッセージフィルタリング** | ボットメッセージ、メッセージ編集、テキストなしメッセージを除外 |
| **ドキュメントインデックス** | メッセージデータをOpenSearchにインデックス（自動でベクトル化） |

### 処理されるSlackイベント

| イベントタイプ | 処理内容 |
|--------------|---------|
| `url_verification` | Slack Appセットアップ時のチャレンジ応答を返却 |
| `event_callback` (message) | メッセージをOpenSearchにインデックス |

### インデックスされるドキュメント構造

Lambda関数がOpenSearchに送信するドキュメント：

```json
{
  "message_id": "クライアントメッセージID",
  "channel_id": "チャンネルID",
  "user_id": "送信ユーザーID",
  "text": "メッセージ本文",
  "timestamp": "メッセージタイムスタンプ（ts）",
  "thread_ts": "スレッドタイムスタンプ（スレッド返信の場合）",
  "team_id": "ワークスペースID",
  "event_time": "イベント発生時刻（Unix時間）"
}
```

インジェストパイプライン処理後、最終的にインデックスに保存されるドキュメント：

```json
{
  "message_id": "クライアントメッセージID",
  "channel_id": "チャンネルID",
  "user_id": "送信ユーザーID",
  "text": "メッセージ本文",
  "text_embedding": [0.123, -0.456, ...],
  "timestamp": "メッセージタイムスタンプ（ts）",
  "thread_ts": "スレッドタイムスタンプ（スレッド返信の場合）",
  "team_id": "ワークスペースID",
  "event_time": "イベント発生時刻（Unix時間）"
}
```

> **Note**: `text_embedding`フィールドはインジェストパイプライン（`slack-ingest-pipeline`）によって`text`フィールドから自動生成されます。Titan Embeddings V2モデルが1024次元のベクトルを生成します。

### 環境変数

| キー | 説明 | デフォルト値 |
|-----|------|------------|
| `OPENSEARCH_ENDPOINT` | OpenSearch Serviceのエンドポイント | - |
| `INDEX_NAME` | インデックス名 | `slack-messages` |
| `INGEST_PIPELINE` | インジェストパイプライン名 | `slack-ingest-pipeline` |
| `SLACK_SIGNING_SECRET` | Slack署名シークレット（オプション） | - |

---

## 2. SlackHybridSearch-Search

OpenSearch Serviceに対してハイブリッド検索（BM25キーワード検索 + k-NNベクトル検索）を実行する関数です。

### 処理フロー

```
API Gateway → Lambda → OpenSearch Service
                              ↓
                       AI Connectors（Neural Search）
                       （OpenSearchがBedrockを呼び出してクエリをベクトル化）
                              ↓
                       ハイブリッド検索実行
                              ↓
                       検索結果を返却
```

> **ポイント**: AI Connectorsを活用することで、Lambda側でBedrockを呼び出す必要がありません。OpenSearchが直接Bedrockと連携してクエリをベクトル化します。

### サポートする検索モード

| モード | 説明 | スコア計算 |
|-------|------|-----------|
| `hybrid` | キーワード検索とベクトル検索を組み合わせ（デフォルト） | BM25 × 0.3 + k-NN × 0.7 |
| `keyword` | BM25によるキーワード検索のみ | BM25スコア |
| `vector` | k-NNによるベクトル検索のみ | コサイン類似度 |

### APIエンドポイント

**GET /search**
```
GET /search?q=検索クエリ&mode=hybrid&size=10
```

**POST /search**
```json
{
  "query": "検索クエリ",
  "mode": "hybrid",
  "size": 10
}
```

### レスポンス形式

```json
{
  "query": "検索クエリ",
  "mode": "hybrid",
  "total": 42,
  "results": [
    {
      "score": 0.95,
      "message_id": "xxx",
      "channel_id": "C01234567",
      "user_id": "U01234567",
      "text": "メッセージ本文",
      "timestamp": "1234567890.123456",
      "thread_ts": null
    }
  ]
}
```

### 環境変数

| キー | 説明 | デフォルト値 |
|-----|------|------------|
| `OPENSEARCH_ENDPOINT` | OpenSearch Serviceのエンドポイント | - |
| `INDEX_NAME` | インデックス名 | `slack-messages` |
| `SEARCH_PIPELINE` | 検索パイプライン名 | `hybrid-search-pipeline` |
| `MODEL_ID` | AI ConnectorのモデルID（Neural Search用） | - |

---

## CDKでの実装

本リポジトリでは、これらのLambda関数をCDKで定義しています。

参照: `cdk/lib/slack-hybrid-search-stack.ts`

### 共通設定

| 項目 | 値 |
|-----|-----|
| ランタイム | Python 3.12 |
| メモリ | 256 MB |
| タイムアウト | 30 秒 |
| 実行ロール | `SlackHybridSearchLambdaRole` |
| ログ保持期間 | 1週間 |

### Slack Webhook Lambda

```typescript
const slackWebhookLambda = new lambda.Function(this, 'SlackWebhookLambda', {
  functionName: 'SlackHybridSearch-SlackWebhook',
  runtime: lambda.Runtime.PYTHON_3_12,
  handler: 'handler.lambda_handler',
  code: lambda.Code.fromAsset(slackWebhookLambdaPath, {
    bundling: {
      image: lambda.Runtime.PYTHON_3_12.bundlingImage,
      local: {
        tryBundle(outputDir: string) {
          execSync(`pip install -r ${path.join(slackWebhookLambdaPath, 'requirements.txt')} -t ${outputDir} --no-cache-dir`);
          execSync(`cp -r ${slackWebhookLambdaPath}/* ${outputDir}`);
          return true;
        },
      },
    },
  }),
  role: lambdaRole,
  timeout: cdk.Duration.seconds(30),
  memorySize: 256,
  environment: {
    OPENSEARCH_ENDPOINT: domain.domainEndpoint,
    INDEX_NAME: 'slack-messages',
    INGEST_PIPELINE: 'slack-ingest-pipeline',
  },
  logRetention: logs.RetentionDays.ONE_WEEK,
});
```

### Search Lambda

```typescript
const searchLambda = new lambda.Function(this, 'SearchLambda', {
  functionName: 'SlackHybridSearch-Search',
  runtime: lambda.Runtime.PYTHON_3_12,
  handler: 'handler.lambda_handler',
  code: lambda.Code.fromAsset(searchLambdaPath, {
    bundling: {
      image: lambda.Runtime.PYTHON_3_12.bundlingImage,
      local: {
        tryBundle(outputDir: string) {
          execSync(`pip install -r ${path.join(searchLambdaPath, 'requirements.txt')} -t ${outputDir} --no-cache-dir`);
          execSync(`cp -r ${searchLambdaPath}/* ${outputDir}`);
          return true;
        },
      },
    },
  }),
  role: lambdaRole,
  timeout: cdk.Duration.seconds(30),
  memorySize: 256,
  environment: {
    OPENSEARCH_ENDPOINT: domain.domainEndpoint,
    INDEX_NAME: 'slack-messages',
    SEARCH_PIPELINE: 'hybrid-search-pipeline',
  },
  logRetention: logs.RetentionDays.ONE_WEEK,
});
```

---

## 依存ライブラリ

両方のLambda関数で使用する依存ライブラリ:

| ライブラリ | バージョン | 用途 |
|-----------|----------|------|
| `opensearch-py` | >=2.4.0 | OpenSearch Serviceへの接続 |
| `requests-aws4auth` | >=1.2.0 | AWS SigV4認証 |
| `requests` | >=2.31.0 | HTTPリクエスト |
| `urllib3` | >=1.26.0,<2.0.0 | HTTP接続（opensearch-pyの依存） |

> **注意**: これらは純粋なPythonパッケージのため、Dockerなしでのローカルバンドリングが可能です。

---

## AI Connectors使用時のアーキテクチャ上のメリット

AI Connectors（Neural Search）を使用することで、以下のメリットがあります：

| 項目 | 従来方式 | AI Connectors使用時 |
|------|---------|-------------------|
| クエリのベクトル化 | Lambda → Bedrock | OpenSearch内部で自動実行 |
| Lambda の Bedrock 権限 | 必要 | **不要** |
| Lambda のコード | Bedrock呼び出しコードが必要 | シンプル（テキストを渡すだけ） |
| レイテンシ | Lambda→Bedrock→OpenSearchの2ホップ | Lambda→OpenSearchの1ホップ |
| コスト | Lambda実行時間が長い | Lambda実行時間が短縮 |

---

## ソースコード

- Slack Webhook Lambda: `cdk/lambda/slack_webhook/handler.py`
- Search Lambda: `cdk/lambda/search/handler.py`
