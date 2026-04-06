# OpenSearch AI Connectors について

## 概要

OpenSearch AI Connectors は、**ML Commons プラグイン**の機能で、外部の機械学習プラットフォームでホストされているモデルに接続するための仕組みです。OpenSearch 2.9 で導入され、**ニューラル検索（セマンティック検索）** やRAGなどのAI機能を実現します。

## 主な特徴

- **外部MLモデルとの連携**: Amazon Bedrock、OpenAI、Cohere、SageMaker等に接続
- **リモート推論**: MLモデルを外部サービスでホストし、OpenSearchから呼び出し
- **自動デプロイ**: OpenSearch 2.13以降、初回のPredict APIリクエスト時に自動デプロイ
- **再利用可能**: 1つのコネクタを複数のモデルで共有可能

## サポートされているプラットフォーム

| プラットフォーム | 用途 |
|-----------------|------|
| Amazon Bedrock | Titan Embeddings、Claude等の基盤モデル |
| Amazon SageMaker | カスタムMLモデルのホスティング |
| OpenAI | ChatGPT、GPT-4、Embeddings |
| Cohere | Embed、Command等のLLM |
| Azure OpenAI | Azure上のOpenAIモデル |

---

## 本プロジェクトでの利用

本リポジトリでは、**Amazon Bedrock Titan Embeddings V2** に接続するAI Connectorを使用しています。

### 構成

```
OpenSearch Service
    └── AI Connector (Bedrock Titan)
            └── Model (Titan Embeddings V2)
                    ├── Ingest Pipeline (インジェスト時のベクトル化)
                    └── Search Pipeline (検索時のベクトル化)
```

### コネクタの設定

本プロジェクトで使用しているコネクタの設定は以下の通りです：

```json
{
  "name": "Bedrock Titan Connector",
  "description": "Connector for Amazon Bedrock Titan Embeddings V2",
  "version": "1",
  "protocol": "aws_sigv4",
  "credential": {
    "roleArn": "arn:aws:iam::【アカウントID】:role/OpenSearchBedrockRole"
  },
  "parameters": {
    "region": "ap-northeast-1",
    "service_name": "bedrock",
    "model": "amazon.titan-embed-text-v2:0"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "https://bedrock-runtime.ap-northeast-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke",
      "request_body": "{ \"inputText\": \"${parameters.inputText}\", \"dimensions\": 1024, \"normalize\": true }",
      "pre_process_function": "【カスタム Painless スクリプト】",
      "post_process_function": "【カスタム Painless スクリプト】"
    }
  ]
}
```

> **重要**: Neural Search（検索時のベクトル化）を使用する場合、カスタムの `pre_process_function` と `post_process_function` が**必須**です。詳細は [AI Connector の Pre/Post Process Function](./AI_Connector_PreProcess.md) を参照してください。

### 設定項目の説明

| 項目 | 値 | 説明 |
|------|-----|------|
| `protocol` | `aws_sigv4` | AWS SigV4認証を使用 |
| `credential.roleArn` | `OpenSearchBedrockRole` | OpenSearchがBedrock呼び出しに使用するIAMロール |
| `parameters.region` | `ap-northeast-1` | Bedrockのリージョン |
| `parameters.service_name` | `bedrock` | AWSサービス名 |
| `parameters.model` | `amazon.titan-embed-text-v2:0` | 使用するモデル |
| `dimensions` | `1024` | 出力ベクトルの次元数 |
| `normalize` | `true` | ベクトルの正規化を有効化 |
| `pre_process_function` | カスタム Painless スクリプト | Neural Search の入力を Bedrock 形式に変換 |
| `post_process_function` | カスタム Painless スクリプト | Bedrock のレスポンスを OpenSearch 形式に変換 |

---

## 主要なAPI

### 1. コネクタの作成
```
POST /_plugins/_ml/connectors/_create
```
外部MLプラットフォームへのコネクタを作成。

### 2. コネクタの検索
```
GET /_plugins/_ml/connectors/_search
```

### 3. コネクタの削除
```
DELETE /_plugins/_ml/connectors/{connector_id}
```

---

## コネクタの種類

### スタンドアロンコネクタ（本プロジェクトで使用）
- 複数のモデルで再利用可能
- コネクタインデックスに保存
- 推奨される方式

### 内部コネクタ
- モデル登録時に直接定義
- 単一モデル専用

---

## ニューラル検索との統合

AI Connectors は以下の ML 推論プロセッサと連携します：

| プロセッサ | 処理タイミング | 用途 |
|-----------|--------------|------|
| **Ingest Processor** | ドキュメント取り込み時 | テキストをベクトル化してインデックス |
| **Search Request Processor** | 検索クエリ受信時 | クエリテキストをベクトル化 |
| **Search Response Processor** | 検索結果返却前 | リランキング等の後処理 |

### 処理フロー

```
【インジェスト時】
テキスト → Ingest Pipeline → AI Connector → Bedrock → ベクトル → インデックス保存

【検索時】
クエリ → Neural Query → AI Connector → Bedrock → ベクトル → k-NN検索 → 結果
```

---

## Workflow API との統合

本プロジェクトでは、**Workflow API（Flow Framework）** を使用して、AI Connectorを含む全リソースを一括で作成しています。

### Workflow テンプレートでの定義

`scripts/workflow-template.json` で以下のリソースを定義：

1. **create_connector** - AI Connectorの作成
2. **register_model** - モデルの登録
3. **deploy_model** - モデルのデプロイ
4. **create_ingest_pipeline** - Ingest Pipelineの作成
5. **create_index** - インデックスの作成
6. **create_search_pipeline** - Search Pipelineの作成

### 依存関係

```
create_connector
       ↓
register_model (connector_id を参照)
       ↓
deploy_model (model_id を参照)
       ↓
create_ingest_pipeline (model_id を参照)
       ↓
create_index (pipeline_id を参照)
       ↓
create_search_pipeline
```

---

## IAMロールの設定

AI Connectorが Bedrock を呼び出すには、適切なIAMロールが必要です。

### OpenSearchBedrockRole

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "bedrock:InvokeModel",
      "Resource": "arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  ]
}
```

信頼ポリシー：
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

詳細は `doc/iam.md` を参照してください。

---

## 参考リンク

- [Connecting to externally hosted models - OpenSearch Documentation](https://docs.opensearch.org/latest/ml-commons-plugin/remote-models/index/)
- [Creating connectors for third-party ML platforms](https://docs.opensearch.org/latest/ml-commons-plugin/remote-models/connectors/)
- [Supported connectors - OpenSearch Documentation](https://docs.opensearch.org/latest/ml-commons-plugin/remote-models/supported-connectors/)
- [Power neural search with AI/ML connectors in Amazon OpenSearch Service](https://aws.amazon.com/blogs/big-data/power-neural-search-with-ai-ml-connectors-in-amazon-opensearch-service/)
- [Amazon OpenSearch Service ML connectors for AWS services](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-amazon-connector.html)
