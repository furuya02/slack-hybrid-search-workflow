# OpenSearch Serverless における ML Commons プラグイン機能の制限

## 概要

OpenSearch Serverless は、OpenSearch Service（マネージドドメイン）と比較して、**ML Commons プラグイン**の機能に制限があります。本ドキュメントでは、その制限事項と OpenSearch Service との違いを整理します。

## OpenSearch Serverless と OpenSearch Service の比較

### 機能比較表

| 機能 | OpenSearch Serverless | OpenSearch Service |
|------|----------------------|-------------------|
| 基本的なインデックス操作 | ✅ | ✅ |
| k-NN ベクトル検索 | ✅ | ✅ |
| ML Commons プラグイン | △（制限あり） | ✅ フルサポート |
| AI Connectors | △（追加権限設定が必要） | ✅ |
| Workflow API | △（ML関連ステップに制限） | ✅ |
| Ingest Pipeline（ML処理） | △ | ✅ |
| Search Pipeline（ML処理） | △ | ✅ |

### Serverless の ML 機能制限

公式ドキュメントによると、OpenSearch Serverless では以下の制限があります：

- **ローカルモデルは非サポート**（リモートモデルのみ使用可能）
- **Re-index Workflow ステップは非サポート**
- ML 機能を使用するには**追加の権限設定**が必要

### Serverless で ML 機能を使用する場合の権限設定

データアクセスポリシーに以下の権限を追加する必要があります：

```json
{
  "Rules": [
    {
      "Resource": ["model/collection_name/*"],
      "Permission": [
        "aoss:DescribeMLResource",
        "aoss:CreateMLResource",
        "aoss:UpdateMLResource",
        "aoss:DeleteMLResource",
        "aoss:ExecuteMLResource"
      ],
      "ResourceType": "model"
    }
  ],
  "Principal": ["arn:aws:iam::account_id:role/role_name"]
}
```

## 公式ドキュメント

### OpenSearch Serverless

| ドキュメント | URL |
|-------------|-----|
| サポートされる操作とプラグイン | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-genref.html |
| Machine Learning の設定 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-configure-machine-learning.html |
| Workflows の設定 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-configure-workflows.html |

### OpenSearch Service

| ドキュメント | URL |
|-------------|-----|
| エンジンバージョン別プラグイン | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/supported-plugins.html |
| Machine Learning | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml.html |
| ML Connectors の作成 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-create.html |
| AWS サービス用 ML Connectors | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-amazon-connector.html |

## コスト比較

| サービス | 構成 | 1日あたり |
|---------|------|----------|
| OpenSearch Serverless | 0.5 OCU × 2 | ~$5.76 |
| OpenSearch Service | t3.medium × 1 | ~$1.75 |

OpenSearch Service の方が約70%安価です（最小構成の場合）。

## 選択の指針

### OpenSearch Serverless が適している場合

- 基本的なインデックス操作と検索のみ
- ML 機能を使用しない
- インフラ管理を完全に任せたい

### OpenSearch Service が適している場合

- AI Connectors を使用したい
- Workflow API で ML 関連リソースを一括作成したい
- Ingest Pipeline / Search Pipeline で ML 処理を行いたい
- ML Commons プラグインの全機能を使用したい

---

## 参考：実際に発生した事例

本リポジトリの開発中、OpenSearch Serverless で AI Connectors を使用しようとした際に以下の問題が発生しました。

### 発生した事象

```bash
# Connector 作成 API の実行
curl -X POST "https://${COLLECTION_ENDPOINT}/_plugins/_ml/connectors/_create" \
    --aws-sigv4 "aws:amz:ap-northeast-1:aoss" \
    ...

# エラーレスポンス
{
  "status": 403,
  "error": "Forbidden"
}
```

### 調査結果

| API | 結果 |
|-----|------|
| `PUT /test-index` | 200 OK（成功） |
| `POST /_plugins/_ml/connectors/_create` | 403 Forbidden |
| `GET /_plugins/_ml/config` | "no handler found" |

データアクセスポリシーに `aoss:*MLResource` 権限が不足していた可能性があります。

### 対応

本プロジェクトでは、ML Commons プラグインの全機能を確実に使用するため、**OpenSearch Service（マネージドドメイン）に切り替え**ました。これにより、AI Connectors と Workflow API が問題なく動作するようになりました。
