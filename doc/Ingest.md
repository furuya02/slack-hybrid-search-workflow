# インジェスト（メッセージ投入）時の処理フロー

## 概要

Slack メッセージが OpenSearch に登録される際、**Ingest Pipeline** によってテキストが自動的にベクトル化されます。

## 処理フロー図

```
┌─────────────────┐
│ Lambda function │
│ (Slack Webhook) │
└────────┬────────┘
         │ ドキュメント送信
         │ { "text": "会議は15時から" }
         ▼
┌─────────────────────────────────────────────────────────┐
│  OpenSearch Service                                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Ingest Pipeline (slack-ingest-pipeline)           │  │
│  │   └── text_embedding プロセッサ                   │  │
│  │           │                                        │  │
│  │           │ model_id で指定されたモデルを使用     │  │
│  │           ▼                                        │  │
│  │  ┌─────────────────┐                              │  │
│  │  │ Model (deployed)│                              │  │
│  │  │   │             │                              │  │
│  │  │   │ connector_id で接続                        │  │
│  │  │   ▼             │                              │  │
│  │  │ ┌─────────────┐ │                              │  │
│  │  │ │AI Connector │ │                              │  │
│  │  │ └──────┬──────┘ │                              │  │
│  │  └────────┼────────┘                              │  │
│  │           │                                        │  │
│  └───────────┼────────────────────────────────────────┘  │
│              │ Bedrock API 呼び出し                      │
└──────────────┼───────────────────────────────────────────┘
               ▼
      ┌─────────────────┐
      │ Amazon Bedrock  │
      │ Titan Embed V2  │
      └────────┬────────┘
               │ ベクトル返却 [0.12, 0.34, ...]
               ▼
┌─────────────────────────────────────────────────────────┐
│  OpenSearch Service                                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Ingest Pipeline                                    │  │
│  │   ドキュメントにベクトルを追加                      │  │
│  │   {                                                │  │
│  │     "text": "会議は15時から",                      │  │
│  │     "text_embedding": [0.12, 0.34, ...]            │  │
│  │   }                                                │  │
│  └───────────────────────────────────────────────────┘  │
│              │                                           │
│              ▼                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Index (slack-messages)                             │  │
│  │   ドキュメントを保存                               │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 使用されるリソースの関係

| リソース | Workflow での作成 | インジェスト時の役割 |
|---------|------------------|---------------------|
| AI Connector | `create_connector` | Bedrock への接続定義（認証、URL、リクエスト形式） |
| Model | `register_model` + `deploy_model` | Connector を使用可能な状態にしたもの |
| Ingest Pipeline | `create_ingest_pipeline` | ドキュメント登録時に text_embedding プロセッサを実行 |
| Index | `create_index` | ベクトル化されたドキュメントを保存 |

---

## リソース間の依存関係

```
┌─────────────────┐
│  AI Connector   │ ← Bedrock への接続情報を定義
└────────┬────────┘
         │ connector_id
         ▼
┌─────────────────┐
│     Model       │ ← Connector を参照（function_name: "remote"）
│   (deployed)    │
└────────┬────────┘
         │ model_id
         ▼
┌─────────────────┐
│ Ingest Pipeline │ ← Model を使用して text → text_embedding 変換
└────────┬────────┘
         │ default_pipeline として設定
         ▼
┌─────────────────┐
│     Index       │ ← ドキュメント登録時に Ingest Pipeline を自動適用
└─────────────────┘
```

---

## 処理の詳細

### 1. Lambda からドキュメント送信

Lambda 関数（`SlackHybridSearch-SlackWebhook`）が Slack イベントを受信し、OpenSearch にドキュメントを送信します。

```python
# cdk/lambda/slack_webhook/handler.py より
document = {
    'message_id': slack_event.get('client_msg_id'),
    'channel_id': slack_event.get('channel'),
    'user_id': slack_event.get('user'),
    'text': slack_event.get('text', ''),
    'timestamp': slack_event.get('ts'),
    'thread_ts': slack_event.get('thread_ts'),
    'team_id': body.get('team_id'),
    'event_time': body.get('event_time'),
}

# Ingest Pipeline を指定してインデックス
client.index(
    index=INDEX_NAME,
    body=document,
    pipeline=INGEST_PIPELINE,  # "slack-ingest-pipeline"
    refresh=True
)
```

**送信されるドキュメント:**
```json
POST /slack-messages/_doc?pipeline=slack-ingest-pipeline
{
  "message_id": "msg-001",
  "channel_id": "C12345",
  "user_id": "U12345",
  "text": "明日の会議は15時からです",
  "timestamp": "1700000000.000001",
  "thread_ts": null,
  "team_id": "T001",
  "event_time": 1700000000
}
```

### 2. Ingest Pipeline が text_embedding プロセッサを実行

```json
{
  "processors": [{
    "text_embedding": {
      "model_id": "${{deploy_model.model_id}}",
      "field_map": { "text": "text_embedding" }
    }
  }]
}
```

- `text` フィールドの値を取得
- `model_id` で指定されたモデル（= AI Connector 経由で Bedrock）を呼び出し
- 結果を `text_embedding` フィールドに格納

### 3. AI Connector が Bedrock を呼び出し

```json
POST https://bedrock-runtime.ap-northeast-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke
{
  "inputText": "明日の会議は15時からです",
  "dimensions": 1024,
  "normalize": true
}
```

> **Note**: インジェスト時は `text_embedding` プロセッサが直接 Bedrock を呼び出すため、`pre_process_function` は使用されません。

### 4. Bedrock がベクトルを返却

```json
{
  "embedding": [0.123, 0.456, ..., 0.789]  // 1024次元
}
```

### 5. ドキュメントが Index に保存

```json
{
  "message_id": "msg-001",
  "channel_id": "C12345",
  "user_id": "U12345",
  "text": "明日の会議は15時からです",
  "text_embedding": [0.123, 0.456, ..., 0.789],
  "timestamp": "1700000000.000001",
  "thread_ts": null,
  "team_id": "T001",
  "event_time": 1700000000
}
```

---

## ポイント

### Lambda は Bedrock を直接呼び出さない

| 従来の方式 | AI Connectors 方式（今回） |
|-----------|--------------------------|
| Lambda → Bedrock → OpenSearch | Lambda → OpenSearch → Bedrock |
| Lambda に Bedrock 権限が必要 | Lambda に Bedrock 権限は**不要** |
| アプリケーション側でベクトル化 | OpenSearch 内部でベクトル化 |

### default_pipeline の設定

Index 作成時に `default_pipeline` を設定することで、ドキュメント登録時に Ingest Pipeline が自動適用されます。

```json
{
  "settings": {
    "index": {
      "knn": true,
      "default_pipeline": "slack-ingest-pipeline"
    }
  }
}
```

これにより、Lambda は単純にドキュメントを送信するだけで、ベクトル化は OpenSearch 側で自動的に行われます。

### pipeline パラメータの明示的指定

本プロジェクトの Lambda 実装では、`default_pipeline` に加えて、`pipeline` パラメータも明示的に指定しています。

```python
client.index(
    index=INDEX_NAME,
    body=document,
    pipeline=INGEST_PIPELINE,  # 明示的に指定
    refresh=True
)
```

これにより、`default_pipeline` が設定されていない場合でも確実に Ingest Pipeline が適用されます。

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `cdk/lambda/slack_webhook/handler.py` | Slack Webhook Lambda 関数（インジェスト処理） |
| `scripts/workflow-template.json` | Ingest Pipeline の定義を含む |
| `scripts/load-sample-data.sh` | サンプルデータ投入スクリプト |
| `doc/Lambda.md` | Lambda 関数の詳細 |
| `doc/workflow-template.md` | Workflow テンプレートの構成 |

---

## 参考リンク

- [OpenSearch Ingest Pipelines](https://opensearch.org/docs/latest/ingest-pipelines/)
- [OpenSearch Text Embedding Processor](https://opensearch.org/docs/latest/ingest-pipelines/processors/text-embedding/)
- [Amazon Bedrock Titan Embeddings](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
