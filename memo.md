## ブログにしたい内容
  - 「7〜10ステップ → 1〜2ステップ」という構築の簡略化
  - 2025年8月の新機能（Workflow API、AI Connectors）の実践的な使い方
  - OpenSearch 側で直接 Bedrock を呼び出す構成

---

# 実装時の気づきメモ

ブログ執筆時に参考になる、実装中の気づきや注意点をまとめています。

## OpenSearch Serverless 関連

### コスト面での重要な注意点

1. **一時停止機能がない**
   - OpenSearch Serverless には「一時停止」機能が存在しない
   - 課金を止めるにはコレクションを削除するしかない
   - 検証目的なら、使わない時間帯は削除して再作成する運用が必要

2. **最小 OCU の課金**
   - インデックス用: 最小 0.5 OCU
   - 検索用: 最小 0.5 OCU
   - 合計 1 OCU 分が常時課金される（$0.24 × 24h = $5.76/日）

3. **OpenSearch Ingestion を使わない理由**
   - ブログ案にある通り、Lambda から直接投入することでコスト削減
   - Ingestion Pipeline は別途 OCU が必要になる

### ポリシー設定の注意点

1. **3種類のポリシーが必要**
   - Encryption Policy（暗号化）
   - Network Policy（ネットワークアクセス）
   - Data Access Policy（データアクセス権限）

2. **ポリシー名の制約**
   - 小文字英数字とハイフンのみ
   - コレクション名と一貫性を持たせると管理しやすい

3. **Data Access Policy の Principal**
   - Lambda の実行ロール ARN
   - OpenSearch が Bedrock を呼び出すためのロール ARN
   - 手動で Workflow API を実行するためのプリンシパル（IAM ユーザー/ロール）
   - 全て含める必要がある

## Bedrock 関連

### Titan Embeddings V2 の設定

1. **事前に有効化が必要**
   - AWS コンソール → Bedrock → Model access で有効化
   - リージョンごとに有効化が必要

2. **埋め込みベクトルの次元**
   - Titan V2 は 1024 次元がデフォルト
   - `dimensions` パラメータで 256, 384, 1024 から選択可能
   - 低次元にするとコスト削減になるが精度は下がる

3. **IAM ロールの信頼ポリシー**
   - `ml.opensearchservice.amazonaws.com` を指定
   - `opensearchservice.amazonaws.com` ではない点に注意

## Lambda 関連

### Layer のビルド

1. **Docker を使うべき理由**
   - macOS でビルドした依存関係は Linux Lambda で動かない場合がある
   - `public.ecr.aws/sam/build-python3.12` イメージを使用推奨

2. **依存関係のバージョン**
   - `urllib3` は 2.x 系だと互換性問題が発生する場合がある
   - `urllib3>=1.26.0,<2.0.0` で固定推奨

### Slack Events API 対応

1. **URL Verification**
   - Slack App 設定時に `challenge` パラメータを返す必要がある
   - これが動かないと Event Subscriptions を有効化できない

2. **署名検証**
   - `X-Slack-Request-Timestamp` と `X-Slack-Signature` で検証
   - API Gateway を通すとヘッダー名が小文字になる場合があるので両方対応

3. **リトライ対応**
   - Slack は 3秒以内にレスポンスがないとリトライする
   - 重い処理は非同期（SQS等）にすべきだが、今回は簡易実装

## ハイブリッド検索関連

### Search Pipeline の重み設定

```json
"weights": [0.3, 0.7]
```

- 第1要素: BM25（キーワード検索）の重み
- 第2要素: k-NN（ベクトル検索）の重み
- ユースケースに応じて調整が必要

### 日本語対応

1. **kuromoji analyzer**
   - OpenSearch Serverless でも使用可能
   - ただし、今回のシンプル実装では `standard` analyzer を使用
   - 日本語の場合は kuromoji に変更推奨

2. **Titan Embeddings と日本語**
   - 日本語テキストも問題なく埋め込み可能
   - ただし、英語と比べると精度は若干落ちる可能性

## CDK 関連

### 依存関係の順序

1. **Security Policy → Collection の順で作成**
   - Collection 作成前に暗号化とネットワークポリシーが必要
   - `addDependency` で明示的に指定

2. **Collection → Data Access Policy の順**
   - Data Access Policy は Collection ARN を参照する
   - こちらも `addDependency` が必要

## その他

### 検証環境でのコスト最小化

1. **使い終わったらすぐ削除**
   ```bash
   ./scripts/cleanup.sh
   ```

2. **再構築は簡単**
   ```bash
   cd cdk && pnpm cdk deploy
   ./scripts/setup-workflow.sh
   ```
   - インデックスデータは消えるが、検証目的なら問題なし

### ブログで強調すべきポイント

1. **Workflow API の価値**
   - 従来 5-7 回の API 呼び出しが必要だった設定が簡略化
   - ただし、今回は手動でステップバイステップ実装
   - Workflow API テンプレートが安定したら、1回の API 呼び出しで完結

2. **サーバーレス完結**
   - EC2 や自前のコンテナなし
   - 運用負荷が低い

3. **コスト管理の重要性**
   - OpenSearch Serverless は「常時課金」
   - 検証目的なら削除が基本
