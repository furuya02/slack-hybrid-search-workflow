#!/bin/bash
set -e

# ===========================================
# Load Sample Data Script
# ===========================================
# Prerequisites:
# - Set DOMAIN_ENDPOINT in .env
# - Workflow setup completed
# ===========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a && source "$PROJECT_ROOT/.env" && set +a
fi

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
INDEX_NAME="${INDEX_NAME:-slack-messages}"
INGEST_PIPELINE="${INGEST_PIPELINE:-slack-ingest-pipeline}"

if [ -z "$DOMAIN_ENDPOINT" ]; then
    echo "Error: DOMAIN_ENDPOINT is required. Set it in .env"
    exit 1
fi

echo "Endpoint: $DOMAIN_ENDPOINT"
echo "Index: $INDEX_NAME"
echo ""

# Index document function
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

echo "Indexing sample messages..."
echo ""

# Channel and user definitions
CH_PROJECT="C0001PROJECT"
CH_TECH="C0002TECH"
CH_GENERAL="C0003GENERAL"
CH_RANDOM="C0004RANDOM"
BASE_TS="1700000000"

# Project management (20 messages)
echo -n "Project (20): "
index_document '{"message_id":"msg-001","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"新規プロジェクトのキックオフミーティングを来週月曜日に開催します","timestamp":"'$BASE_TS'.000001","team_id":"T001"}'
index_document '{"message_id":"msg-002","channel_id":"'$CH_PROJECT'","user_id":"U002","text":"了解しました。会議室は第3会議室でよろしいでしょうか？","timestamp":"'$BASE_TS'.000002","thread_ts":"'$BASE_TS'.000001","team_id":"T001"}'
index_document '{"message_id":"msg-003","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"はい、第3会議室を予約済みです。10時からでお願いします","timestamp":"'$BASE_TS'.000003","thread_ts":"'$BASE_TS'.000001","team_id":"T001"}'
index_document '{"message_id":"msg-004","channel_id":"'$CH_PROJECT'","user_id":"U003","text":"プロジェクトのスケジュールを共有します。全体で3ヶ月を予定しています","timestamp":"'$BASE_TS'.000004","team_id":"T001"}'
index_document '{"message_id":"msg-005","channel_id":"'$CH_PROJECT'","user_id":"U004","text":"マイルストーンは月末ごとに設定する形でしょうか？","timestamp":"'$BASE_TS'.000005","thread_ts":"'$BASE_TS'.000004","team_id":"T001"}'
index_document '{"message_id":"msg-006","channel_id":"'$CH_PROJECT'","user_id":"U003","text":"その通りです。各月末にレビュー会を実施します","timestamp":"'$BASE_TS'.000006","thread_ts":"'$BASE_TS'.000004","team_id":"T001"}'
index_document '{"message_id":"msg-007","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"進捗報告のフォーマットを作成しました。確認をお願いします","timestamp":"'$BASE_TS'.000007","team_id":"T001"}'
index_document '{"message_id":"msg-008","channel_id":"'$CH_PROJECT'","user_id":"U005","text":"タスク管理ツールはJiraを使用する予定です","timestamp":"'$BASE_TS'.000008","team_id":"T001"}'
index_document '{"message_id":"msg-009","channel_id":"'$CH_PROJECT'","user_id":"U002","text":"バックログの整理が完了しました。優先度の確認をお願いします","timestamp":"'$BASE_TS'.000009","team_id":"T001"}'
index_document '{"message_id":"msg-010","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"スプリント計画を立てましょう。2週間サイクルでいかがでしょうか","timestamp":"'$BASE_TS'.000010","team_id":"T001"}'
index_document '{"message_id":"msg-011","channel_id":"'$CH_PROJECT'","user_id":"U003","text":"リスク管理表を更新しました","timestamp":"'$BASE_TS'.000011","team_id":"T001"}'
index_document '{"message_id":"msg-012","channel_id":"'$CH_PROJECT'","user_id":"U004","text":"予算の承認が下りました。調達を開始できます","timestamp":"'$BASE_TS'.000012","team_id":"T001"}'
index_document '{"message_id":"msg-013","channel_id":"'$CH_PROJECT'","user_id":"U005","text":"ベンダーとの打ち合わせを来週水曜日に設定しました","timestamp":"'$BASE_TS'.000013","team_id":"T001"}'
index_document '{"message_id":"msg-014","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"週次の定例会議は毎週金曜日の15時からにしましょう","timestamp":"'$BASE_TS'.000014","team_id":"T001"}'
index_document '{"message_id":"msg-015","channel_id":"'$CH_PROJECT'","user_id":"U002","text":"議事録のテンプレートを作成しました","timestamp":"'$BASE_TS'.000015","team_id":"T001"}'
index_document '{"message_id":"msg-016","channel_id":"'$CH_PROJECT'","user_id":"U003","text":"ステークホルダーへの報告資料を準備中です","timestamp":"'$BASE_TS'.000016","team_id":"T001"}'
index_document '{"message_id":"msg-017","channel_id":"'$CH_PROJECT'","user_id":"U004","text":"品質基準のドキュメントをレビューしてください","timestamp":"'$BASE_TS'.000017","team_id":"T001"}'
index_document '{"message_id":"msg-018","channel_id":"'$CH_PROJECT'","user_id":"U005","text":"テスト計画の策定を開始します","timestamp":"'$BASE_TS'.000018","team_id":"T001"}'
index_document '{"message_id":"msg-019","channel_id":"'$CH_PROJECT'","user_id":"U001","text":"要件定義フェーズが完了しました","timestamp":"'$BASE_TS'.000019","team_id":"T001"}'
index_document '{"message_id":"msg-020","channel_id":"'$CH_PROJECT'","user_id":"U002","text":"設計レビューのスケジュールを調整中です","timestamp":"'$BASE_TS'.000020","team_id":"T001"}'
echo " Done"

# Technical discussions (30 messages)
echo -n "Tech (30): "
index_document '{"message_id":"msg-021","channel_id":"'$CH_TECH'","user_id":"U003","text":"AWSのLambda関数でタイムアウトが発生しています","timestamp":"'$BASE_TS'.000021","team_id":"T001"}'
index_document '{"message_id":"msg-022","channel_id":"'$CH_TECH'","user_id":"U005","text":"メモリを増やしてみてはいかがでしょうか？256MBから512MBに","timestamp":"'$BASE_TS'.000022","thread_ts":"'$BASE_TS'.000021","team_id":"T001"}'
index_document '{"message_id":"msg-023","channel_id":"'$CH_TECH'","user_id":"U003","text":"試してみます。ありがとうございます","timestamp":"'$BASE_TS'.000023","thread_ts":"'$BASE_TS'.000021","team_id":"T001"}'
index_document '{"message_id":"msg-024","channel_id":"'$CH_TECH'","user_id":"U004","text":"Pythonのバージョンを3.12にアップグレードしました","timestamp":"'$BASE_TS'.000024","team_id":"T001"}'
index_document '{"message_id":"msg-025","channel_id":"'$CH_TECH'","user_id":"U001","text":"依存ライブラリの互換性は問題ありませんでしたか？","timestamp":"'$BASE_TS'.000025","thread_ts":"'$BASE_TS'.000024","team_id":"T001"}'
index_document '{"message_id":"msg-026","channel_id":"'$CH_TECH'","user_id":"U004","text":"一部のライブラリを更新する必要がありましたが、解決済みです","timestamp":"'$BASE_TS'.000026","thread_ts":"'$BASE_TS'.000024","team_id":"T001"}'
index_document '{"message_id":"msg-027","channel_id":"'$CH_TECH'","user_id":"U002","text":"APIのレスポンスタイムが遅い問題を調査中です","timestamp":"'$BASE_TS'.000027","team_id":"T001"}'
index_document '{"message_id":"msg-028","channel_id":"'$CH_TECH'","user_id":"U005","text":"CloudWatchのメトリクスを確認しましたか？","timestamp":"'$BASE_TS'.000028","thread_ts":"'$BASE_TS'.000027","team_id":"T001"}'
index_document '{"message_id":"msg-029","channel_id":"'$CH_TECH'","user_id":"U002","text":"確認したところ、データベースへのクエリが遅いようです","timestamp":"'$BASE_TS'.000029","thread_ts":"'$BASE_TS'.000027","team_id":"T001"}'
index_document '{"message_id":"msg-030","channel_id":"'$CH_TECH'","user_id":"U003","text":"インデックスを追加することで改善できるかもしれません","timestamp":"'$BASE_TS'.000030","thread_ts":"'$BASE_TS'.000027","team_id":"T001"}'
index_document '{"message_id":"msg-031","channel_id":"'$CH_TECH'","user_id":"U001","text":"DockerイメージのビルドをGitHub Actionsで自動化しました","timestamp":"'$BASE_TS'.000031","team_id":"T001"}'
index_document '{"message_id":"msg-032","channel_id":"'$CH_TECH'","user_id":"U004","text":"CI/CDパイプラインの設定ファイルを共有してもらえますか？","timestamp":"'$BASE_TS'.000032","thread_ts":"'$BASE_TS'.000031","team_id":"T001"}'
index_document '{"message_id":"msg-033","channel_id":"'$CH_TECH'","user_id":"U005","text":"Terraformでインフラを管理することを提案します","timestamp":"'$BASE_TS'.000033","team_id":"T001"}'
index_document '{"message_id":"msg-034","channel_id":"'$CH_TECH'","user_id":"U002","text":"IaCは良いアイデアですね。CDKも選択肢になりそうです","timestamp":"'$BASE_TS'.000034","thread_ts":"'$BASE_TS'.000033","team_id":"T001"}'
index_document '{"message_id":"msg-035","channel_id":"'$CH_TECH'","user_id":"U003","text":"セキュリティスキャンでいくつかの脆弱性が見つかりました","timestamp":"'$BASE_TS'.000035","team_id":"T001"}'
index_document '{"message_id":"msg-036","channel_id":"'$CH_TECH'","user_id":"U001","text":"緊急度の高いものから対応しましょう","timestamp":"'$BASE_TS'.000036","thread_ts":"'$BASE_TS'.000035","team_id":"T001"}'
index_document '{"message_id":"msg-037","channel_id":"'$CH_TECH'","user_id":"U004","text":"マイクロサービス間の通信にgRPCを採用しました","timestamp":"'$BASE_TS'.000037","team_id":"T001"}'
index_document '{"message_id":"msg-038","channel_id":"'$CH_TECH'","user_id":"U005","text":"RESTと比べてパフォーマンスはどうですか？","timestamp":"'$BASE_TS'.000038","thread_ts":"'$BASE_TS'.000037","team_id":"T001"}'
index_document '{"message_id":"msg-039","channel_id":"'$CH_TECH'","user_id":"U004","text":"約30%の改善が見られました","timestamp":"'$BASE_TS'.000039","thread_ts":"'$BASE_TS'.000037","team_id":"T001"}'
index_document '{"message_id":"msg-040","channel_id":"'$CH_TECH'","user_id":"U002","text":"ログ収集にFluentdを導入しました","timestamp":"'$BASE_TS'.000040","team_id":"T001"}'
index_document '{"message_id":"msg-041","channel_id":"'$CH_TECH'","user_id":"U003","text":"ElasticsearchとKibanaで可視化する予定です","timestamp":"'$BASE_TS'.000041","thread_ts":"'$BASE_TS'.000040","team_id":"T001"}'
index_document '{"message_id":"msg-042","channel_id":"'$CH_TECH'","user_id":"U001","text":"モニタリングダッシュボードを作成しました","timestamp":"'$BASE_TS'.000042","team_id":"T001"}'
index_document '{"message_id":"msg-043","channel_id":"'$CH_TECH'","user_id":"U004","text":"アラートの閾値を設定する必要がありますね","timestamp":"'$BASE_TS'.000043","thread_ts":"'$BASE_TS'.000042","team_id":"T001"}'
index_document '{"message_id":"msg-044","channel_id":"'$CH_TECH'","user_id":"U005","text":"負荷テストの結果を共有します。1000リクエスト/秒まで対応可能です","timestamp":"'$BASE_TS'.000044","team_id":"T001"}'
index_document '{"message_id":"msg-045","channel_id":"'$CH_TECH'","user_id":"U002","text":"Auto Scalingの設定も確認しておきましょう","timestamp":"'$BASE_TS'.000045","thread_ts":"'$BASE_TS'.000044","team_id":"T001"}'
index_document '{"message_id":"msg-046","channel_id":"'$CH_TECH'","user_id":"U003","text":"キャッシュ戦略について議論したいです","timestamp":"'$BASE_TS'.000046","team_id":"T001"}'
index_document '{"message_id":"msg-047","channel_id":"'$CH_TECH'","user_id":"U001","text":"Redisを使ったセッション管理を実装しました","timestamp":"'$BASE_TS'.000047","team_id":"T001"}'
index_document '{"message_id":"msg-048","channel_id":"'$CH_TECH'","user_id":"U004","text":"データベースのバックアップ設定を確認してください","timestamp":"'$BASE_TS'.000048","team_id":"T001"}'
index_document '{"message_id":"msg-049","channel_id":"'$CH_TECH'","user_id":"U005","text":"災害復旧計画のドキュメントを更新しました","timestamp":"'$BASE_TS'.000049","team_id":"T001"}'
index_document '{"message_id":"msg-050","channel_id":"'$CH_TECH'","user_id":"U002","text":"本番環境へのデプロイ手順書を作成中です","timestamp":"'$BASE_TS'.000050","team_id":"T001"}'
echo " Done"

# General conversation (30 messages)
echo -n "General (30): "
index_document '{"message_id":"msg-051","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"おはようございます。今日も一日よろしくお願いします","timestamp":"'$BASE_TS'.000051","team_id":"T001"}'
index_document '{"message_id":"msg-052","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"おはようございます！","timestamp":"'$BASE_TS'.000052","thread_ts":"'$BASE_TS'.000051","team_id":"T001"}'
index_document '{"message_id":"msg-053","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"来週の金曜日は祝日のためお休みです","timestamp":"'$BASE_TS'.000053","team_id":"T001"}'
index_document '{"message_id":"msg-054","channel_id":"'$CH_GENERAL'","user_id":"U004","text":"了解です。スケジュールを調整します","timestamp":"'$BASE_TS'.000054","thread_ts":"'$BASE_TS'.000053","team_id":"T001"}'
index_document '{"message_id":"msg-055","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"社内勉強会の参加者を募集しています。テーマはAI活用です","timestamp":"'$BASE_TS'.000055","team_id":"T001"}'
index_document '{"message_id":"msg-056","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"参加希望です！","timestamp":"'$BASE_TS'.000056","thread_ts":"'$BASE_TS'.000055","team_id":"T001"}'
index_document '{"message_id":"msg-057","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"私も参加します","timestamp":"'$BASE_TS'.000057","thread_ts":"'$BASE_TS'.000055","team_id":"T001"}'
index_document '{"message_id":"msg-058","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"新しいオフィスのレイアウトが決まりました","timestamp":"'$BASE_TS'.000058","team_id":"T001"}'
index_document '{"message_id":"msg-059","channel_id":"'$CH_GENERAL'","user_id":"U004","text":"引っ越しはいつ頃の予定ですか？","timestamp":"'$BASE_TS'.000059","thread_ts":"'$BASE_TS'.000058","team_id":"T001"}'
index_document '{"message_id":"msg-060","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"来月末を予定しています","timestamp":"'$BASE_TS'.000060","thread_ts":"'$BASE_TS'.000058","team_id":"T001"}'
index_document '{"message_id":"msg-061","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"今日の昼食は何にしますか？","timestamp":"'$BASE_TS'.000061","team_id":"T001"}'
index_document '{"message_id":"msg-062","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"近くの新しいラーメン屋に行ってみたいです","timestamp":"'$BASE_TS'.000062","thread_ts":"'$BASE_TS'.000061","team_id":"T001"}'
index_document '{"message_id":"msg-063","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"健康診断の予約をお忘れなく","timestamp":"'$BASE_TS'.000063","team_id":"T001"}'
index_document '{"message_id":"msg-064","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"予約しました。ありがとうございます","timestamp":"'$BASE_TS'.000064","thread_ts":"'$BASE_TS'.000063","team_id":"T001"}'
index_document '{"message_id":"msg-065","channel_id":"'$CH_GENERAL'","user_id":"U004","text":"今週末のチームビルディングイベントの詳細です","timestamp":"'$BASE_TS'.000065","team_id":"T001"}'
index_document '{"message_id":"msg-066","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"楽しみにしています！","timestamp":"'$BASE_TS'.000066","thread_ts":"'$BASE_TS'.000065","team_id":"T001"}'
index_document '{"message_id":"msg-067","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"経費精算の締め切りは今週金曜日です","timestamp":"'$BASE_TS'.000067","team_id":"T001"}'
index_document '{"message_id":"msg-068","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"提出しました","timestamp":"'$BASE_TS'.000068","thread_ts":"'$BASE_TS'.000067","team_id":"T001"}'
index_document '{"message_id":"msg-069","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"新入社員の歓迎会を企画しています","timestamp":"'$BASE_TS'.000069","team_id":"T001"}'
index_document '{"message_id":"msg-070","channel_id":"'$CH_GENERAL'","user_id":"U004","text":"幹事をやります","timestamp":"'$BASE_TS'.000070","thread_ts":"'$BASE_TS'.000069","team_id":"T001"}'
index_document '{"message_id":"msg-071","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"有給休暇の申請システムが更新されました","timestamp":"'$BASE_TS'.000071","team_id":"T001"}'
index_document '{"message_id":"msg-072","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"使い方のマニュアルはありますか？","timestamp":"'$BASE_TS'.000072","thread_ts":"'$BASE_TS'.000071","team_id":"T001"}'
index_document '{"message_id":"msg-073","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"ポータルサイトに掲載されています","timestamp":"'$BASE_TS'.000073","thread_ts":"'$BASE_TS'.000071","team_id":"T001"}'
index_document '{"message_id":"msg-074","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"在宅勤務の申請方法が変更になりました","timestamp":"'$BASE_TS'.000074","team_id":"T001"}'
index_document '{"message_id":"msg-075","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"詳細を確認します","timestamp":"'$BASE_TS'.000075","thread_ts":"'$BASE_TS'.000074","team_id":"T001"}'
index_document '{"message_id":"msg-076","channel_id":"'$CH_GENERAL'","user_id":"U004","text":"今月の目標達成おめでとうございます","timestamp":"'$BASE_TS'.000076","team_id":"T001"}'
index_document '{"message_id":"msg-077","channel_id":"'$CH_GENERAL'","user_id":"U005","text":"チームの皆さんのおかげです","timestamp":"'$BASE_TS'.000077","thread_ts":"'$BASE_TS'.000076","team_id":"T001"}'
index_document '{"message_id":"msg-078","channel_id":"'$CH_GENERAL'","user_id":"U001","text":"来月の予定を共有します","timestamp":"'$BASE_TS'.000078","team_id":"T001"}'
index_document '{"message_id":"msg-079","channel_id":"'$CH_GENERAL'","user_id":"U002","text":"カレンダーに登録しました","timestamp":"'$BASE_TS'.000079","thread_ts":"'$BASE_TS'.000078","team_id":"T001"}'
index_document '{"message_id":"msg-080","channel_id":"'$CH_GENERAL'","user_id":"U003","text":"お疲れ様でした。良い週末を！","timestamp":"'$BASE_TS'.000080","team_id":"T001"}'
echo " Done"

# Random chat (20 messages)
echo -n "Random (20): "
index_document '{"message_id":"msg-081","channel_id":"'$CH_RANDOM'","user_id":"U004","text":"最近読んだ技術書が面白かったので共有します","timestamp":"'$BASE_TS'.000081","team_id":"T001"}'
index_document '{"message_id":"msg-082","channel_id":"'$CH_RANDOM'","user_id":"U005","text":"何という本ですか？","timestamp":"'$BASE_TS'.000082","thread_ts":"'$BASE_TS'.000081","team_id":"T001"}'
index_document '{"message_id":"msg-083","channel_id":"'$CH_RANDOM'","user_id":"U004","text":"「マイクロサービスパターン」という本です","timestamp":"'$BASE_TS'.000083","thread_ts":"'$BASE_TS'.000081","team_id":"T001"}'
index_document '{"message_id":"msg-084","channel_id":"'$CH_RANDOM'","user_id":"U001","text":"週末にハッカソンに参加してきました","timestamp":"'$BASE_TS'.000084","team_id":"T001"}'
index_document '{"message_id":"msg-085","channel_id":"'$CH_RANDOM'","user_id":"U002","text":"何を作ったんですか？","timestamp":"'$BASE_TS'.000085","thread_ts":"'$BASE_TS'.000084","team_id":"T001"}'
index_document '{"message_id":"msg-086","channel_id":"'$CH_RANDOM'","user_id":"U001","text":"AIチャットボットを作りました","timestamp":"'$BASE_TS'.000086","thread_ts":"'$BASE_TS'.000084","team_id":"T001"}'
index_document '{"message_id":"msg-087","channel_id":"'$CH_RANDOM'","user_id":"U003","text":"新しいカフェがオープンしたらしいです","timestamp":"'$BASE_TS'.000087","team_id":"T001"}'
index_document '{"message_id":"msg-088","channel_id":"'$CH_RANDOM'","user_id":"U004","text":"コーヒーが美味しいと評判ですね","timestamp":"'$BASE_TS'.000088","thread_ts":"'$BASE_TS'.000087","team_id":"T001"}'
index_document '{"message_id":"msg-089","channel_id":"'$CH_RANDOM'","user_id":"U005","text":"今度の連休の予定はありますか？","timestamp":"'$BASE_TS'.000089","team_id":"T001"}'
index_document '{"message_id":"msg-090","channel_id":"'$CH_RANDOM'","user_id":"U001","text":"旅行に行く予定です","timestamp":"'$BASE_TS'.000090","thread_ts":"'$BASE_TS'.000089","team_id":"T001"}'
index_document '{"message_id":"msg-091","channel_id":"'$CH_RANDOM'","user_id":"U002","text":"おすすめのプログラミング言語はありますか？","timestamp":"'$BASE_TS'.000091","team_id":"T001"}'
index_document '{"message_id":"msg-092","channel_id":"'$CH_RANDOM'","user_id":"U003","text":"用途によりますが、Pythonは汎用性が高いです","timestamp":"'$BASE_TS'.000092","thread_ts":"'$BASE_TS'.000091","team_id":"T001"}'
index_document '{"message_id":"msg-093","channel_id":"'$CH_RANDOM'","user_id":"U004","text":"TypeScriptも人気ですね","timestamp":"'$BASE_TS'.000093","thread_ts":"'$BASE_TS'.000091","team_id":"T001"}'
index_document '{"message_id":"msg-094","channel_id":"'$CH_RANDOM'","user_id":"U005","text":"最近のAI技術の進歩はすごいですね","timestamp":"'$BASE_TS'.000094","team_id":"T001"}'
index_document '{"message_id":"msg-095","channel_id":"'$CH_RANDOM'","user_id":"U001","text":"ChatGPTの活用方法を模索中です","timestamp":"'$BASE_TS'.000095","thread_ts":"'$BASE_TS'.000094","team_id":"T001"}'
index_document '{"message_id":"msg-096","channel_id":"'$CH_RANDOM'","user_id":"U002","text":"業務効率化に使えそうですね","timestamp":"'$BASE_TS'.000096","thread_ts":"'$BASE_TS'.000094","team_id":"T001"}'
index_document '{"message_id":"msg-097","channel_id":"'$CH_RANDOM'","user_id":"U003","text":"今日は天気が良いですね","timestamp":"'$BASE_TS'.000097","team_id":"T001"}'
index_document '{"message_id":"msg-098","channel_id":"'$CH_RANDOM'","user_id":"U004","text":"散歩日和ですね","timestamp":"'$BASE_TS'.000098","thread_ts":"'$BASE_TS'.000097","team_id":"T001"}'
index_document '{"message_id":"msg-099","channel_id":"'$CH_RANDOM'","user_id":"U005","text":"今年の目標は達成できそうですか？","timestamp":"'$BASE_TS'.000099","team_id":"T001"}'
index_document '{"message_id":"msg-100","channel_id":"'$CH_RANDOM'","user_id":"U001","text":"あと少しで達成できそうです","timestamp":"'$BASE_TS'.000100","thread_ts":"'$BASE_TS'.000099","team_id":"T001"}'
echo " Done"

echo ""
echo "=== Complete: 100 messages indexed ==="
