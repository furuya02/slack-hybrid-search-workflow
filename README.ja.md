# Slack Hybrid Search Workflow

OpenSearch Serverless の AI Connectors を活用したハイブリッド検索システムを Workflow API で構築するサンプルコードです。

> **Note**: このリポジトリは、ブログ記事「[OpenSearch Serverless] AI Connectors を活用したハイブリッド検索システムを Workflow API で構築」のサンプルコードです。

## 概要

このプロジェクトは、Slack のメッセージを OpenSearch Serverless に取り込み、キーワード検索（BM25）とベクトル検索（k-NN）を組み合わせたハイブリッド検索を実現します。

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
# .env を編集して AWS 認証情報を設定

# CDK デプロイ
cd cdk
pnpm install
pnpm cdk bootstrap  # 初回のみ
pnpm cdk deploy
```

デプロイ完了後、出力される `CollectionEndpoint` と `BedrockRoleArn` を `.env` に設定します。

### 2. ハイブリッド検索リソースの作成（Workflow API）

OpenSearch Flow Framework を使用して、1回のAPI呼び出しで全リソースを作成します。

```bash
cd ..
./scripts/setup-workflow-api.sh
```

> **Note**: 個別APIを使う方法は `setup-hybrid-search.sh` を参照してください。

### 3. サンプルデータで検索テスト

Slack 風のサンプルデータ（100件）を投入してハイブリッド検索を試します。

```bash
# サンプルデータを OpenSearch に投入
./scripts/load-sample-data.sh
```

投入後、検索 API をテストできます。

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

### リソース削除

```bash
# 検証終了後、全リソースを削除
./scripts/cleanup.sh
```

> **重要**: OpenSearch Serverless には一時停止機能がありません。
> コストを止めるにはコレクションを削除する必要があります。

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

## （参考）実際の Slack 連携

実際の Slack ワークスペースと連携する場合は、以下の手順で設定します。

1. https://api.slack.com/apps で新しいアプリを作成
2. **OAuth & Permissions** で以下のスコープを追加:
   - `channels:history` - チャンネルのメッセージを読み取る
   - `channels:read` - チャンネル情報を読み取る
3. **Event Subscriptions** を有効化
4. Request URL に CDK 出力の `SlackWebhookUrl` を設定
5. **Subscribe to bot events** で `message.channels` を追加
6. アプリをワークスペースにインストール

## ライセンス

MIT
