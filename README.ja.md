# Slack Hybrid Search Workflow

OpenSearch Service の AI Connectors を活用したハイブリッド検索システムを Workflow API で構築するサンプルコードです。

> **Note**: このリポジトリは、ブログ記事「[OpenSearch Service] AI Connectors を活用したハイブリッド検索システムを Workflow API で構築」のサンプルコードです。

## 概要

このプロジェクトは、Slack のメッセージを OpenSearch Service に取り込み、キーワード検索（BM25）とベクトル検索（k-NN）を組み合わせたハイブリッド検索を実現します。

### 特徴

- **ハイブリッド検索**: キーワード一致と意味的類似性の両方で検索
- **Workflow API**: 1回のAPI呼び出しで全リソースを一括作成
- **サーバーレス**: 全てマネージドサービスで構成、EC2不要
- **日本語対応**: Amazon Titan Embeddings V2 による日本語埋め込み

## アーキテクチャ

![](images/ingest.png)

![](images/search.png)

## 前提条件

- AWS CLI 設定済み
- Node.js 18.x 以上
- pnpm
- Docker（Lambda Layer ビルド用、推奨）
- Amazon Bedrock で Titan Embeddings V2 が有効化済み

## クイックスタート

### 1. CDK デプロイ

```bash
# リポジトリのクローン
git clone https://github.com/furuya02/slack-hybrid-search-workflow.git
cd slack-hybrid-search-workflow

# 環境変数の設定
cp .env.example .env

# CDK デプロイ
cd cdk
pnpm install
pnpm cdk bootstrap  # 初回のみ
pnpm cdk deploy
```

デプロイ完了後、出力される `DomainEndpoint` と `OpenSearchBedrockRoleArn` を `.env` に設定します。

### 2. ハイブリッド検索リソースの作成（Workflow API）

OpenSearch Flow Framework を使用して、1回のAPI呼び出しで全リソースを作成します。

```bash
cd ..
./scripts/setup-workflow-api.sh
```

Workflow のステータスを確認し、`model_id` を取得します。

```bash
DOMAIN_ENDPOINT="<CDK出力の DomainEndpoint>"
WORKFLOW_ID="<setup-workflow-api.sh 出力の workflow_id>"

curl -s -X GET "https://${DOMAIN_ENDPOINT}/_plugins/_flow_framework/workflow/${WORKFLOW_ID}/_status" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" | jq .
```

`state: "COMPLETED"` を確認し、`resources_created` から `model_id` をメモします。

> **Note**: 個別APIを使う方法は `setup-hybrid-search.sh` を参照してください。

### 3. Lambda の環境変数を更新

Workflow で作成された `model_id` を Search Lambda に設定します。

```bash
aws lambda update-function-configuration \
    --function-name SlackHybridSearch-Search \
    --environment "Variables={OPENSEARCH_ENDPOINT=<DomainEndpoint>,INDEX_NAME=slack-messages,SEARCH_PIPELINE=hybrid-search-pipeline,MODEL_ID=<model_id>}"
```

> **重要**: この手順を行わないと、`hybrid` モードと `vector` モードの検索が動作しません。

### 4. サンプルデータで検索テスト

Slack 風のサンプルデータ（100件）を投入してハイブリッド検索を試します。

```bash
# サンプルデータを OpenSearch に投入
./scripts/load-sample-data.sh
```

投入後、検索 API をテストします。

```bash
# API エンドポイントを取得
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name SlackHybridSearchStack \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
    --output text)

# ハイブリッド検索をテスト
curl -s -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "Lambda が遅い", "mode": "hybrid"}' \
  | jq -r '.results[] | "\(.score | tostring | .[0:6]) | \(.text)"'

# キーワード検索
curl -s -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "会議", "mode": "keyword"}' \
  | jq -r '.results[] | "\(.score | tostring | .[0:6]) | \(.text)"'

# ベクトル検索（意味的類似性）
curl -s -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "パフォーマンスを改善したい", "mode": "vector"}' \
  | jq -r '.results[] | "\(.score | tostring | .[0:6]) | \(.text)"'
```

### 5. サンプルデータの削除

Slack 連携を確認する前に、サンプルデータを削除します。

```bash
# インデックス内の全ドキュメントを削除
curl -s -X POST "https://${DOMAIN_ENDPOINT}/slack-messages/_delete_by_query" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"query": {"match_all": {}}}' | jq .

# 削除確認（0件になっていることを確認）
curl -s -X GET "https://${DOMAIN_ENDPOINT}/slack-messages/_count" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" | jq .
```

### 6. Slack App の設定

#### 6-1. Slack App の作成

1. https://api.slack.com/apps で **Create New App** をクリック
2. **From scratch** を選択し、アプリ名とワークスペースを指定

#### 6-2. OAuth & Permissions の設定

1. 左メニューから **OAuth & Permissions** を選択
2. **Scopes** セクションで **Bot Token Scopes** に以下を追加:
   - `channels:history` - チャンネルのメッセージを読み取る
   - `channels:read` - チャンネル情報を読み取る

#### 6-3. Event Subscriptions の設定

1. 左メニューから **Event Subscriptions** を選択
2. **Enable Events** を **On** に切り替え
3. **Request URL** に CDK 出力の `SlackWebhookUrl` を設定
   ```
   https://xxxxxxxxxx.execute-api.ap-northeast-1.amazonaws.com/prod/slack/events
   ```
   > URL を入力すると Slack が検証リクエストを送信し、Lambda が応答して **Verified** と表示されます。

4. **Subscribe to bot events** で **Add Bot User Event** をクリックし、`message.channels` を追加
5. **Save Changes** をクリック

#### 6-4. アプリのインストール

1. 左メニューから **Install App** を選択
2. **Install to Workspace** をクリック
3. 権限を確認して **許可する** をクリック

#### 6-5. チャンネルにアプリを追加

1. Slack でメッセージを監視したいチャンネルを開く
2. チャンネル名をクリック → **インテグレーション** タブ → **アプリを追加する**
3. 作成したアプリを追加

### 7. Slack 連携の動作確認

#### 7-1. Slack でメッセージを投稿

監視対象のチャンネルでメッセージを投稿します。

```
今日の定例会議は15時からです。議事録は後で共有します。
```

#### 7-2. インデックスへの登録を確認

```bash
# ドキュメント数を確認
curl -s -X GET "https://${DOMAIN_ENDPOINT}/slack-messages/_count" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" | jq .
```

#### 7-3. 検索で投稿したメッセージを確認

```bash
# キーワード検索
curl -s -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "定例会議", "mode": "keyword"}' \
  | jq -r '.results[] | "\(.score | tostring | .[0:6]) | \(.text)"'

# ハイブリッド検索（意味的にも検索）
curl -s -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "ミーティングの予定", "mode": "hybrid"}' \
  | jq -r '.results[] | "\(.score | tostring | .[0:6]) | \(.text)"'
```

> **ポイント**: ハイブリッド検索では「定例会議」と「ミーティング」のような同義語でもヒットします。

## 検索モード

| モード | 説明 | ユースケース |
|--------|------|-------------|
| `hybrid` | BM25 + k-NN の組み合わせ | 一般的な検索（推奨） |
| `keyword` | BM25 のみ | 専門用語、固有名詞の検索 |
| `vector` | k-NN のみ | 意味的類似検索、曖昧な表現 |

## コスト管理

### 概算コスト（24時間稼働時）

| サービス | 内訳 | 1日あたり |
|---------|------|----------|
| OpenSearch Service | t3.medium.search × 1台 | ~$1.75 |
| Bedrock Titan | 使用量に応じて | ~$0.01 |
| Lambda + API Gateway | 無料枠内 | $0.00 |

**合計: 約 $1.76/日 = 約 $12/週**

### リソース削除

```bash
# 検証終了後、全リソースを削除
./scripts/cleanup.sh
```

> **重要**: コストを止めるにはドメインを削除する必要があります。

## ディレクトリ構成

```
slack-hybrid-search-workflow/
├── cdk/                          # CDK インフラコード
│   ├── bin/
│   │   └── cdk.ts
│   ├── lib/
│   │   └── slack-hybrid-search-stack.ts
│   └── lambda/
│       ├── slack_webhook/        # Slack イベント受信
│       │   ├── handler.py
│       │   └── requirements.txt
│       └── search/               # 検索 API
│           ├── handler.py
│           └── requirements.txt
├── scripts/
│   ├── setup-workflow-api.sh     # Workflow API でセットアップ（推奨）
│   ├── workflow-template.json    # ワークフロー定義テンプレート
│   ├── setup-hybrid-search.sh    # 個別API でセットアップ（参考）
│   ├── load-sample-data.sh       # サンプルデータ投入
│   └── cleanup.sh                # リソース削除
├── images/                       # アーキテクチャ図
├── README.md
└── README.ja.md
```

## トラブルシューティング

### 検索結果が返らない

- Workflow の設定が完了しているか確認
- インデックスにドキュメントが投入されているか確認
- OpenSearch Dashboards でインデックスの状態を確認

### ベクトル検索が動作しない

- Bedrock の Titan Embeddings V2 が有効化されているか確認
- IAM ロールに Bedrock への権限があるか確認

## ライセンス

MIT
