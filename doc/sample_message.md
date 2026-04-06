# サンプルメッセージのセットアップ

ハイブリッド検索の動作を確認するためのサンプルメッセージ（100件）を投入する手順です。

## 概要

| 項目 | 説明 |
|-----|------|
| 投入件数 | 100件 |
| 投入方法 | OpenSearch Service に直接インデックス |
| 使用スクリプト | `scripts/load-sample-data.sh` |
| 認証 | AWS SigV4 認証（サービス名: `es`） |

---

## 前提条件

| 項目 | 説明 |
|------|------|
| CDKスタック | `SlackHybridSearchStack` がデプロイ済み |
| Workflow | `setup-workflow-api.sh` でリソース作成済み |
| `.env` ファイル | `DOMAIN_ENDPOINT` を設定 |
| AWS認証情報 | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` が環境変数に設定済み |

---

## 実行方法

```bash
cd /path/to/slack-hybrid-search-workflow
./scripts/load-sample-data.sh
```

---

## スクリプト構成

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# .env 読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a && source "$PROJECT_ROOT/.env" && set +a
fi

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
INDEX_NAME="${INDEX_NAME:-slack-messages}"
INGEST_PIPELINE="${INGEST_PIPELINE:-slack-ingest-pipeline}"

# ドキュメントインデックス関数
index_document() {
    local doc="$1"
    curl -s -X POST \
        "https://${DOMAIN_ENDPOINT}/$INDEX_NAME/_doc?pipeline=$INGEST_PIPELINE" \
        --aws-sigv4 "aws:amz:$AWS_REGION:es" \
        --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
        -H "Content-Type: application/json" \
        -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
        -d "$doc" > /dev/null 2>&1
    echo -n "."
    sleep 0.3
}
```

### ポイント

| 項目 | 説明 |
|------|------|
| `?pipeline=$INGEST_PIPELINE` | インジェストパイプラインを指定（テキストを自動ベクトル化） |
| `--aws-sigv4 "aws:amz:$AWS_REGION:es"` | OpenSearch Service 用の SigV4 認証（サービス名: `es`） |
| `sleep 0.3` | レート制限対策 |

---

## サンプルメッセージ一覧

### カテゴリ別内訳

| カテゴリ | チャンネル | 件数 | 内容 |
|---------|-----------|------|------|
| プロジェクト管理 | `C0001PROJECT` | 20件 | キックオフ、スケジュール、進捗報告、タスク管理 |
| 技術的な議論 | `C0002TECH` | 30件 | AWS、Python、API、CI/CD、セキュリティ |
| 一般的な会話 | `C0003GENERAL` | 30件 | 挨拶、休暇、イベント、お知らせ |
| 雑談 | `C0004RANDOM` | 20件 | 趣味、天気、おすすめ |

### ドキュメント構造

```json
{
  "message_id": "msg-001",
  "channel_id": "C0001PROJECT",
  "user_id": "U001",
  "text": "新規プロジェクトのキックオフミーティングを来週月曜日に開催します",
  "timestamp": "1700000000.000001",
  "thread_ts": null,
  "team_id": "T001"
}
```

> **Note**: `text_embedding` フィールドはインジェストパイプライン（`slack-ingest-pipeline`）によって `text` フィールドから自動生成されます。

### スレッド返信の例

```json
{
  "message_id": "msg-002",
  "channel_id": "C0001PROJECT",
  "user_id": "U002",
  "text": "了解しました。会議室は第3会議室でよろしいでしょうか？",
  "timestamp": "1700000000.000002",
  "thread_ts": "1700000000.000001",
  "team_id": "T001"
}
```

---

## ハイブリッド検索の効果を示すメッセージ例

サンプルデータには、ハイブリッド検索の効果を確認しやすいメッセージが含まれています。

| キーワード | 同義語・関連語 | メッセージ例 |
|-----------|---------------|-------------|
| 会議 | ミーティング、打ち合わせ | 「キックオフミーティングを開催」「定例会議は金曜日」 |
| 遅い | タイムアウト、パフォーマンス | 「レスポンスタイムが遅い」「タイムアウトが発生」 |
| 共有 | 報告、連絡 | 「スケジュールを共有します」「進捗報告」 |
| 確認 | レビュー、チェック | 「確認をお願いします」「コードを確認しました」 |

---

## 検索テストケース

サンプルデータ投入後、以下のクエリでハイブリッド検索の効果を確認できます。

### テストケース1: 完全一致

```bash
# 「会議」で検索 → キーワード検索でもヒット
curl -s -X GET "${API_GATEWAY_URL}/search?q=会議&mode=hybrid&size=3" | jq '.results'
```

### テストケース2: 同義語検索

```bash
# 「打ち合わせ」で検索 → 「会議」「ミーティング」もヒットするはず
curl -s -X GET "${API_GATEWAY_URL}/search?q=打ち合わせ&mode=hybrid&size=3" | jq '.results'
```

### テストケース3: 意味的検索

```bash
# 「システムが重い」で検索 → 「タイムアウト」「レスポンスが遅い」がヒット
curl -s -X GET "${API_GATEWAY_URL}/search?q=システムが重い&mode=hybrid&size=3" | jq '.results'
```

### テストケース4: 検索モードの比較

```bash
# 同じクエリで3つのモードを比較
for mode in keyword vector hybrid; do
  echo "=== Mode: $mode ==="
  curl -s -X GET "${API_GATEWAY_URL}/search?q=プロジェクトの進捗&mode=$mode&size=3" | jq '.results[].text'
done
```

---

## 期待される結果の違い

| クエリ | keyword | vector | hybrid |
|-------|---------|--------|--------|
| 「会議」 | 「会議」を含むもののみ | 「ミーティング」等も含む | 両方を統合 |
| 「遅延」 | ヒットなし | 「遅い」「タイムアウト」がヒット | ベクトル検索の結果 |
| 「プロジェクト管理」 | 「プロジェクト」を含むもの | 関連する話題全般 | バランスの取れた結果 |

---

## 出力例

```
Endpoint: search-slack-hybrid-search-xxxxx.ap-northeast-1.es.amazonaws.com
Index: slack-messages

Indexing sample messages...

Project (20): .................... Done
Tech (30): .............................. Done
General (30): .............................. Done
Random (20): .................... Done

=== Complete: 100 messages indexed ===
```

---

## 投入件数の確認

```bash
curl -s -X GET \
    "https://${DOMAIN_ENDPOINT}/slack-messages/_count" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
    -H "x-amz-security-token: $AWS_SESSION_TOKEN" | jq .
```

レスポンス例：
```json
{
  "count": 100,
  "_shards": {
    "total": 2,
    "successful": 2,
    "skipped": 0,
    "failed": 0
  }
}
```

---

## サンプルデータの削除

Slack 連携テスト前にサンプルデータを削除する場合は、`_delete_by_query` API を使用します。

```bash
# インデックス内の全ドキュメントを削除
curl -s -X POST "https://${DOMAIN_ENDPOINT}/slack-messages/_delete_by_query" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"query": {"match_all": {}}}' | jq .
```

レスポンス例：
```json
{
  "took": 45,
  "timed_out": false,
  "total": 100,
  "deleted": 100,
  "batches": 1,
  "version_conflicts": 0,
  "noops": 0,
  "failures": []
}
```

削除確認：
```bash
curl -s -X GET "https://${DOMAIN_ENDPOINT}/slack-messages/_count" \
    --aws-sigv4 "aws:amz:ap-northeast-1:es" \
    --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
    -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" | jq .
```

> **Note**: この方法はインデックス内のドキュメントのみを削除します。インデックスやパイプラインなどのリソースは残ります。

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `scripts/load-sample-data.sh` | サンプルデータ投入スクリプト |
| `scripts/cleanup.sh` | 全リソース削除スクリプト（CDK destroy） |
| `.env` | 環境変数設定ファイル |

