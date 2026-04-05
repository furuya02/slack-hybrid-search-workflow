# Slack Hybrid Search Workflow

OpenSearch Serverless + Amazon Bedrock を使用した Slack メッセージのハイブリッド検索システム

## 概要

このプロジェクトは、Slack のメッセージを OpenSearch Serverless に取り込み、キーワード検索（BM25）とベクトル検索（k-NN）を組み合わせたハイブリッド検索を実現します。

### 特徴

- **ハイブリッド検索**: キーワード一致と意味的類似性の両方で検索
- **サーバーレス**: 全てマネージドサービスで構成、EC2不要
- **コスト最適化**: 検証時以外は削除してコストを抑制可能
- **日本語対応**: Amazon Titan Embeddings V2 による日本語埋め込み

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────────┐
│                        OpenSearch Serverless                         │
│                                                                      │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│   │ AI Connector│─▶│   Model     │─▶│  Ingest     │                 │
│   │ (Bedrock)   │  │  Register   │  │  Pipeline   │                 │
│   └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                            │                         │
│                                            ▼                         │
│                    ┌─────────────┐  ┌─────────────┐                 │
│                    │   Search    │◀─│    Index    │                 │
│                    │  Pipeline   │  │  (Vector)   │                 │
│                    └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────┐     ┌─────────────┐
│   Slack     │────▶│ API Gateway │
│ Events API  │     │  + Lambda   │
└─────────────┘     └─────────────┘
```

## 前提条件

- AWS CLI 設定済み
- Node.js 18.x 以上
- pnpm
- Docker（Lambda Layer ビルド用、推奨）
- Slack ワークスペース管理者権限
- Amazon Bedrock で Titan Embeddings V2 が有効化済み

## クイックスタート

### 1. リポジトリのクローン

```bash
git clone https://github.com/your-username/slack-hybrid-search-workflow.git
cd slack-hybrid-search-workflow
```

### 2. 環境変数の設定

```bash
cp .env.example .env
# .env を編集して AWS 認証情報を設定
```

### 3. Lambda Layer のビルド

```bash
./scripts/build-layer.sh
```

### 4. CDK デプロイ

```bash
cd cdk
pnpm install
pnpm cdk bootstrap  # 初回のみ
pnpm cdk deploy
```

### 5. Workflow の設定

CDK デプロイ後、OpenSearch の Workflow を設定します：

```bash
./scripts/setup-workflow.sh
```

### 6. サンプルデータでテスト（Slack連携なし）

Slack を設定する前に、サンプルデータでハイブリッド検索を試すことができます：

```bash
# サンプルデータを OpenSearch に直接投入
./scripts/load-sample-data.sh
```

投入後、検索 API をテストできます：

```bash
# API エンドポイントを取得
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name SlackHybridSearchStack \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
    --output text)

# ハイブリッド検索をテスト
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "Lambda が遅い", "mode": "hybrid"}'

# キーワード検索
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "コスト削減", "mode": "keyword"}'

# ベクトル検索（意味的類似性）
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "パフォーマンスを改善したい", "mode": "vector"}'
```

### 7. Slack App の設定

実際の Slack ワークスペースと連携する場合：

1. https://api.slack.com/apps で新しいアプリを作成
2. **OAuth & Permissions** で以下のスコープを追加:
   - `channels:history` - チャンネルのメッセージを読み取る
   - `channels:read` - チャンネル情報を読み取る
   - `chat:write` - メッセージを投稿する（ダミーデータ投稿用）
3. **Event Subscriptions** を有効化
4. Request URL に CDK 出力の `SlackWebhookUrl` を設定
5. **Subscribe to bot events** で `message.channels` を追加
6. アプリをワークスペースにインストール

### 8. Slack にダミーメッセージを投稿してテスト

Slack 連携後、ダミーメッセージを投稿してインデックス化をテストします：

```bash
# .env に以下を設定
# SLACK_BOT_TOKEN=xoxb-your-bot-token
# SLACK_CHANNEL_ID=C0123456789

# ダミーメッセージを自動投稿
./scripts/post-to-slack.sh
```

または、`scripts/sample-messages.txt` の内容を手動で Slack チャンネルに投稿してください。

### 9. 検索のテスト

```bash
# GET リクエスト
curl "https://your-api-endpoint/prod/search?q=検索クエリ&mode=hybrid"

# POST リクエスト
curl -X POST "https://your-api-endpoint/prod/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "検索クエリ", "mode": "hybrid", "size": 10}'
```

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
| OpenSearch Serverless | 0.5 OCU × 2 × $0.24/h | ~$5.76 |
| Bedrock Titan | 使用量に応じて | ~$0.01 |
| Lambda + API Gateway | 無料枠内 | $0.00 |

**合計: 約 $5.77/日 = 約 $40/週**

### コスト削減

```bash
# 現在のコスト状況を確認
./scripts/check-cost.sh

# 検証終了後、全リソースを削除
./scripts/cleanup.sh
```

> **重要**: OpenSearch Serverless には一時停止機能がありません。
> コストを止めるにはコレクションを削除する必要があります。

## ディレクトリ構成

```
slack-hybrid-search-workflow/
├── cdk/                      # CDK インフラコード
│   ├── bin/
│   │   └── cdk.ts
│   ├── lib/
│   │   └── slack-hybrid-search-stack.ts
│   └── lambda/
│       ├── slack_webhook/    # Slack イベント受信
│       │   └── handler.py
│       ├── search/           # 検索 API
│       │   └── handler.py
│       └── layer/            # 共通依存関係
│           └── requirements.txt
├── scripts/
│   ├── build-layer.sh        # Lambda Layer ビルド
│   ├── setup-workflow.sh     # Workflow API 設定
│   ├── load-sample-data.sh   # サンプルデータ投入（Slack連携なし）
│   ├── post-to-slack.sh      # Slack へダミーメッセージ投稿
│   ├── sample-messages.txt   # サンプルメッセージ一覧
│   ├── cleanup.sh            # リソース削除
│   └── check-cost.sh         # コスト確認
├── README.md
├── README.ja.md
└── memo.md                   # 実装時の気づきメモ
```

## トラブルシューティング

### Slack URL Verification が失敗する

- API Gateway のエンドポイント URL が正しいか確認
- Lambda のログで `challenge` レスポンスが返っているか確認

### 検索結果が返らない

- Workflow の設定が完了しているか確認
- インデックスにドキュメントが投入されているか確認
- OpenSearch Dashboards でインデックスの状態を確認

### ベクトル検索が動作しない

- Bedrock の Titan Embeddings V2 が有効化されているか確認
- IAM ロールに Bedrock への権限があるか確認

## ライセンス

MIT
