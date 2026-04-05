#!/bin/bash
set -e

# ===========================================
# Post Sample Messages to Slack
# ===========================================
# This script posts sample messages to a Slack channel.
# Messages will be picked up by the webhook and indexed to OpenSearch.
#
# Prerequisites:
# - SLACK_BOT_TOKEN environment variable set
# - SLACK_CHANNEL_ID environment variable set
# - Bot has chat:write permission
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

if [ -z "$SLACK_BOT_TOKEN" ]; then
    echo "Error: SLACK_BOT_TOKEN is not set."
    echo ""
    echo "Set it in .env file or export it:"
    echo "  export SLACK_BOT_TOKEN=xoxb-your-bot-token"
    exit 1
fi

if [ -z "$SLACK_CHANNEL_ID" ]; then
    echo "Error: SLACK_CHANNEL_ID is not set."
    echo ""
    echo "Find your channel ID in Slack (right-click channel > View channel details)"
    echo "Set it in .env file or export it:"
    echo "  export SLACK_CHANNEL_ID=C0123456789"
    exit 1
fi

echo "============================================="
echo "Posting Sample Messages to Slack"
echo "============================================="
echo "Channel ID: $SLACK_CHANNEL_ID"
echo ""

# Sample messages (same as load-sample-data.sh)
messages=(
    "Lambda のコールドスタートが遅いんですが、何か対策ありますか？"
    "Provisioned Concurrency を設定すると改善しますよ。ただしコストは上がります。"
    "Lambda の実行時間が30秒を超えてタイムアウトになることがあります。メモリを増やしたら解決しました。"
    "デプロイが遅い問題、CI/CDパイプラインの見直しで改善できました"
    "GitHub Actions のキャッシュを有効にしたらビルド時間が半分になりました"
    "本番環境へのリリース作業に時間がかかっています。自動化を検討中です。"
    "DynamoDB のクエリが遅いです。GSI を追加したほうがいいでしょうか？"
    "アクセスパターンを分析して、適切なインデックス設計をしましょう。"
    "RDS の接続数が上限に達してエラーが発生しています。コネクションプーリングを導入します。"
    "OpenSearch でベクトル検索を試しています。Bedrock と連携するのが便利ですね。"
    "キーワード検索だと表記揺れに弱いので、ハイブリッド検索を導入しました"
    "全文検索と意味検索を組み合わせると、検索精度が大幅に向上しますね"
    "API でエラーが発生したときのリトライ処理を実装しました。指数バックオフを使っています。"
    "例外処理のベストプラクティスについてドキュメントを作成中です"
    "AWS のコスト削減について検討しています。使っていないリソースを洗い出しました。"
    "Savings Plans を購入してコストを30%削減できました"
    "開発環境は夜間と週末に自動停止するようにしました。月額費用がかなり下がりました。"
    "IAM ポリシーの最小権限の原則を徹底しましょう。不要な権限は削除してください。"
    "シークレット情報は Secrets Manager で管理するようにしました"
    "WAF のルールを更新して、不正アクセスをブロックするようにしました"
)

post_message() {
    local text="$1"
    local response
    response=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"channel\": \"$SLACK_CHANNEL_ID\",
            \"text\": \"$text\"
        }")

    if echo "$response" | grep -q '"ok":true'; then
        echo -n "."
    else
        echo ""
        echo "Error posting message: $response"
    fi
}

echo "Posting ${#messages[@]} messages..."
echo -n "Progress: "

for msg in "${messages[@]}"; do
    post_message "$msg"
    # Small delay to avoid rate limiting
    sleep 1
done

echo ""
echo ""
echo "============================================="
echo "Done!"
echo "============================================="
echo ""
echo "Posted ${#messages[@]} messages to Slack."
echo ""
echo "Messages will be automatically indexed to OpenSearch"
echo "via the Slack Events API webhook."
echo ""
echo "Wait a few seconds, then test the search API."
echo ""
