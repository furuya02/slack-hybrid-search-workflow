# workflow-template.json の構成

このドキュメントでは、`scripts/workflow-template.json` の構造と各ノードの役割を説明します。

## ノード一覧

| No | ノードID | type | 実行される API | 役割 |
|----|---------|------|---------------|------|
| 1 | `create_connector` | `create_connector` | `POST /_plugins/_ml/connectors/_create` | AI Connector 作成 |
| 2 | `register_model` | `register_remote_model` | `POST /_plugins/_ml/models/_register` | モデル登録 |
| 3 | `deploy_model` | `deploy_model` | `POST /_plugins/_ml/models/{id}/_deploy` | モデルデプロイ |
| 4 | `create_ingest_pipeline` | `create_ingest_pipeline` | `PUT /_ingest/pipeline/{name}` | インジェストパイプライン作成 |
| 5 | `create_index` | `create_index` | `PUT /{index_name}` | インデックス作成 |
| 6 | `create_search_pipeline` | `create_search_pipeline` | `PUT /_search/pipeline/{name}` | 検索パイプライン作成 |

### 各ノードの説明

| No | 説明 |
|----|------|
| 1 | Bedrock Titan Embeddings V2 への接続定義を作成。認証方式（aws_sigv4）、エンドポイントURL、リクエスト形式、pre/post_process_function を定義 |
| 2 | Connector を使用するリモートモデルを OpenSearch に登録。`function_name: "remote"` で外部サービス利用を指定 |
| 3 | 登録したモデルを有効化。リモートモデルの場合、実際のモデルはロードせず「使用可能」状態にするのみ |
| 4 | ドキュメント登録時に `text` フィールドを自動ベクトル化し `text_embedding` に保存するパイプライン |
| 5 | k-NN対応インデックスを作成。`knn: true` でベクトル検索を有効化、`default_pipeline` でインジェスト時の自動ベクトル化を設定 |
| 6 | ハイブリッド検索のスコア正規化パイプライン。BM25（30%）と k-NN（70%）のスコアを統合 |

---

## 依存関係

```
create_connector
       │
       ▼ connector_id
register_model
       │
       ▼ model_id
deploy_model
       │
       ▼ model_id
create_ingest_pipeline
       │
       ▼ pipeline_id
create_index
       │
       ▼ index_name
create_search_pipeline
```

---

## 各ノードの詳細

### 1. create_connector

Bedrock への接続情報を定義します。

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `protocol` | `aws_sigv4` | AWS署名v4認証 |
| `credential.roleArn` | `${BEDROCK_ROLE_ARN}` | OpenSearchがBedrockを呼び出す際に使用するIAMロール |
| `parameters.region` | `${AWS_REGION}` | Bedrockのリージョン |
| `parameters.service_name` | `bedrock` | AWSサービス名 |
| `parameters.model` | `amazon.titan-embed-text-v2:0` | 使用するBedrock埋め込みモデル |
| `request_body.dimensions` | `1024` | 出力ベクトルの次元数 |
| `request_body.normalize` | `true` | ベクトルの正規化を有効化 |
| `pre_process_function` | カスタム Painless スクリプト | Neural Search の入力を Bedrock 形式に変換 |
| `post_process_function` | カスタム Painless スクリプト | Bedrock のレスポンスを OpenSearch 形式に変換 |

> **重要**: Neural Search を使用する場合、カスタムの `pre_process_function` と `post_process_function` が**必須**です。詳細は [AI Connector の Pre/Post Process Function](./AI_Connector_PreProcess.md) を参照してください。

### 2. register_model

Connector を使用するモデルを登録します。

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `name` | `Titan Embeddings V2` | モデル名 |
| `function_name` | `remote` | 外部サービス（Bedrock）を使用 |
| `connector_id` | 自動取得 | `create_connector` から引き継ぎ |

### 3. deploy_model

モデルを使用可能な状態にします。

| モデルタイプ | 動作 |
|-------------|------|
| **ローカルモデル** | OpenSearchノードにモデルをロード |
| **リモートモデル（今回）** | 登録を「アクティブ」状態にするのみ |

### 4. create_ingest_pipeline

ドキュメント登録時の自動処理を定義します。

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `pipeline_id` | `slack-ingest-pipeline` | パイプライン名 |
| `model_id` | `${{deploy_model.model_id}}` | デプロイされたモデルのIDを参照 |
| `field_map` | `text → text_embedding` | 入力→出力フィールドのマッピング |

**処理フロー:**
```
入力: { "text": "会議は15時から" }
  ↓ [text_embedding プロセッサ]
出力: { "text": "会議は15時から", "text_embedding": [0.12, 0.34, ...] }
```

> **Note**: `model_id` は `${{deploy_model.model_id}}` という構文で、前のノードで作成されたモデルIDを自動的に参照します。

### 5. create_index

ハイブリッド検索に対応したインデックスを作成します。

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `index_name` | `slack-messages` | インデックス名 |
| `knn` | `true` | ベクトル検索を有効化 |
| `default_pipeline` | `slack-ingest-pipeline` | 登録時に自動適用 |
| `text_embedding.type` | `knn_vector` | ベクトルフィールド |
| `text_embedding.dimension` | `1024` | Titan V2 の次元数 |
| `method.name` | `hnsw` | Hierarchical Navigable Small World |
| `method.engine` | `faiss` | Facebook AI Similarity Search |
| `method.space_type` | `l2` | ユークリッド距離 |

**フィールド定義:**

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

### 6. create_search_pipeline

ハイブリッド検索のスコア統合を定義します。

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `pipeline_id` | `hybrid-search-pipeline` | パイプライン名 |
| `normalization.technique` | `min_max` | スコアを 0〜1 に正規化 |
| `combination.technique` | `arithmetic_mean` | 加重平均で統合 |
| `weights` | `[0.3, 0.7]` | BM25: 30%, k-NN: 70% |

**スコア計算:**
```
検索クエリ: "会議の議事録"
    │
    ├── BM25検索（キーワード）→ スコア正規化
    │
    └── k-NN検索（ベクトル）→ スコア正規化
    │
    ▼ [normalization-processor]
    │
    最終スコア = BM25正規化スコア × 0.3 + k-NN正規化スコア × 0.7
```

---

## previous_node_inputs による依存値の自動引き渡し

```json
{
  "id": "register_model",
  "previous_node_inputs": {
    "create_connector": "connector_id"
  }
}
```

`previous_node_inputs` を使用すると、前のノードで作成されたリソースのIDが自動的に次のノードに渡されます。これにより、スクリプトでIDを手動管理する必要がなくなります。

### 引き渡される値

| ノード | 受け取る値 | 渡し元 |
|--------|-----------|--------|
| `register_model` | `connector_id` | `create_connector` |
| `deploy_model` | `model_id` | `register_model` |
| `create_ingest_pipeline` | `model_id` | `deploy_model` |
| `create_index` | `pipeline_id` | `create_ingest_pipeline` |
| `create_search_pipeline` | `index_name` | `create_index` |

---

## 環境変数

テンプレート内で使用される環境変数：

| 変数 | 説明 | 設定場所 |
|------|------|----------|
| `${BEDROCK_ROLE_ARN}` | OpenSearchがBedrockを呼び出す際のIAMロールARN | `.env` / CDK出力 |
| `${AWS_REGION}` | AWSリージョン（例: `ap-northeast-1`） | `.env` |

`scripts/setup-workflow-api.sh` 実行時に、これらの変数が実際の値に置換されます。

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `scripts/workflow-template.json` | ワークフロー定義テンプレート（本ドキュメントの対象） |
| `scripts/setup-workflow-api.sh` | テンプレートを使用してWorkflowを作成・実行 |
| `doc/Workflow_API.md` | Workflow API の概要と使い方 |
| `doc/setup-workflow-api_sh.md` | setup-workflow-api.sh の詳細解説 |
| `doc/AI_Connector_PreProcess.md` | pre/post_process_function の詳細 |

---

## 参考リンク

- [OpenSearch Flow Framework - Workflow Templates](https://opensearch.org/docs/latest/automating-configurations/workflow-templates/)
- [OpenSearch ML Commons - Connectors](https://opensearch.org/docs/latest/ml-commons-plugin/remote-models/connectors/)
- [Amazon Bedrock Titan Embeddings](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
