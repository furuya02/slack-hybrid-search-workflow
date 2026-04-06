# OpenSearch Serverless で AI Connector が使用できない問題

## 概要

OpenSearch Serverless では **ML Commons プラグイン**の機能が制限されており、AI Connectors を使用したハイブリッド検索システムの構築で問題が発生しました。

## 発生した事象

### 症状

OpenSearch Serverless コレクションに対して AI Connector の作成 API を実行すると、**403 Forbidden** エラーが発生しました。

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

### 調査過程

1. **データアクセスポリシーの確認・更新**
   - `aoss:*` 権限を付与 → 解決せず

2. **OpenSearch Dashboards での直接テスト**

   | API | 結果 |
   |-----|------|
   | `PUT /test-index` | 200 OK（成功） |
   | `POST /_plugins/_ml/connectors/_create` | 403 Forbidden |
   | `GET /_plugins/_ml/config` | "no handler found" |

3. **結論**
   - `/_plugins/_ml/*` エンドポイントが正常に動作しない
   - データアクセスポリシーに `aoss:CreateMLResource` 等の権限設定が不足していた可能性

## 公式ドキュメント

### OpenSearch Serverless

| ドキュメント | URL |
|-------------|-----|
| サポートされる操作とプラグイン | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-genref.html |
| Machine Learning の設定 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-configure-machine-learning.html |
| Workflows の設定 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-configure-workflows.html |

### OpenSearch Service（マネージドドメイン）

| ドキュメント | URL |
|-------------|-----|
| エンジンバージョン別プラグイン | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/supported-plugins.html |
| Machine Learning | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml.html |
| ML Connectors の作成 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-create.html |
| AWS サービス用 ML Connectors | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ml-amazon-connector.html |

## OpenSearch Serverless の ML 機能制限

公式ドキュメントによると、OpenSearch Serverless でも一部の ML 機能はサポートされていますが、以下の制限があります：

- **ローカルモデルは非サポート**（リモートモデルのみ）
- **Re-index Workflow ステップは非サポート**
- 詳細は「Unsupported Machine Learning APIs and features」を参照

### 必要な権限設定

OpenSearch Serverless で ML 機能を使用するには、データアクセスポリシーに以下の権限が必要です：

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

## 解決策

### 選択肢 1: OpenSearch Service（マネージドドメイン）を使用（今回採用）

ML Commons プラグインをフルサポートする **OpenSearch Service** を使用することで、問題なく AI Connectors と Workflow API を使用できました。

```typescript
// CDK での OpenSearch Service ドメイン作成例
import * as opensearch from 'aws-cdk-lib/aws-opensearch';

const domain = new opensearch.Domain(this, 'Domain', {
  domainName: 'slack-hybrid-search',
  version: opensearch.EngineVersion.OPENSEARCH_2_13,
  capacity: {
    dataNodes: 1,
    dataNodeInstanceType: 't3.medium.search',
  },
  ebs: {
    volumeSize: 10,
    volumeType: ec2.EbsDeviceVolumeType.GP3,
  },
  nodeToNodeEncryption: true,
  encryptionAtRest: { enabled: true },
  enforceHttps: true,
});
```

#### コスト比較

| サービス | 構成 | 1日あたり |
|---------|------|----------|
| OpenSearch Serverless | 0.5 OCU × 2 | ~$5.76 |
| OpenSearch Service | t3.medium × 1 | ~$1.75 |

OpenSearch Service の方が約70%安価です。

### 選択肢 2: OpenSearch Serverless で権限設定を見直す

データアクセスポリシーに `aoss:*MLResource` 権限を追加することで、Serverless でも ML 機能が動作する可能性があります。ただし、今回は検証していません。

### 選択肢 3: Lambda 側でベクトル化

OpenSearch Serverless を維持したい場合は、Lambda 関数内で Bedrock を直接呼び出してベクトル化を行い、OpenSearch にはベクトル付きドキュメントを投入する方式に変更できます。

ただし、この場合は以下の機能が使えません：
- Workflow API による一括リソース作成
- Ingest Pipeline での自動ベクトル化
- Search Pipeline での neural クエリ処理

## まとめ

| 機能 | OpenSearch Serverless | OpenSearch Service |
|------|----------------------|-------------------|
| 基本的なインデックス操作 | ✅ | ✅ |
| k-NN ベクトル検索 | ✅ | ✅ |
| AI Connectors | △（権限設定が必要） | ✅ |
| ML Commons プラグイン | △（制限あり） | ✅ |
| Workflow API | △（制限あり） | ✅ |
| Ingest Pipeline（ML） | △ | ✅ |

**AI Connectors や Workflow API を使用したハイブリッド検索システムを確実に構築する場合は、OpenSearch Service を選択することを推奨します。**
