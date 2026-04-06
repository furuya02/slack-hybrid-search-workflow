# IAMロール・ポリシー構成

このドキュメントでは、Slack Hybrid Search システムで使用するIAMロールとポリシーの構成を説明します。

---

## 作成するロール一覧

| ロール名 | 用途 |
|---------|------|
| `OpenSearchBedrockRole` | OpenSearchがBedrockのモデル（Titan Embeddings V2）を呼び出すために使用 |
| `SlackHybridSearchLambdaRole` | Lambda関数がOpenSearch Serviceにアクセスするために使用 |

---

## 1. OpenSearchBedrockRole

### 信頼ポリシー

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

### 管理ポリシー

なし

### インラインポリシー

**ポリシー名**: `BedrockInvokeModelPolicy`

| 用途 |
|------|
| OpenSearchがBedrock Titan Embeddings V2を呼び出してテキストをベクトル化するため（インジェスト時・検索時の両方） |

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

> **補足**: AI Connectors（Neural Search）を使用すると、OpenSearch内部でテキスト→ベクトル変換が自動実行されます。
> - **インジェスト時**: Ingest Pipelineがドキュメントのテキストをベクトル化
> - **検索時**: Neural Queryがクエリテキストをベクトル化
>
> これにより、Lambda側でBedrockを呼び出す必要がなくなり、アーキテクチャがシンプルになります。

---

## 2. SlackHybridSearchLambdaRole

### 信頼ポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 管理ポリシー

| ポリシー名 | 種類 | 用途 |
|-----------|------|------|
| `AWSLambdaBasicExecutionRole` | AWS管理 | Lambda関数の基本実行権限（CloudWatch Logsへのログ出力） |

### インラインポリシー

**ポリシー名**: `LambdaExecutionPolicy`

| 用途 |
|------|
| Lambda関数からOpenSearch Serviceドメインへのアクセス（ドキュメントの読み書き、検索） |

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpGet",
        "es:ESHttpPost",
        "es:ESHttpPut",
        "es:ESHttpDelete",
        "es:ESHttpHead"
      ],
      "Resource": "arn:aws:es:ap-northeast-1:【アカウントID】:domain/slack-hybrid-search/*"
    }
  ]
}
```

> **補足**: AI Connectors（Neural Search）を使用するため、Lambda側でBedrockを呼び出す必要はありません。クエリのベクトル化はOpenSearch内部で自動実行されます。これにより：
> - Lambda関数のコードがシンプルになる
> - Lambda関数の実行時間が短縮される（Bedrock呼び出しのオーバーヘッドがない）
> - Lambdaに付与する権限が最小限になる（最小権限の原則）

---

## 3. OpenSearch Service ドメインアクセスポリシー

OpenSearch Service ドメインには、以下のプリンシパルからのアクセスを許可するリソースベースポリシーが設定されます。

| プリンシパル | 用途 |
|-------------|------|
| `SlackHybridSearchLambdaRole` | Lambda関数からのドキュメント操作・検索 |
| `OpenSearchBedrockRole` | AI Connectors経由でのBedrock呼び出し |
| 管理者ロール | Workflow API実行、Dashboardsアクセス |

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::【アカウントID】:role/SlackHybridSearchLambdaRole",
          "arn:aws:iam::【アカウントID】:role/OpenSearchBedrockRole",
          "arn:aws:iam::【アカウントID】:role/【管理者ロール名】"
        ]
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:ap-northeast-1:【アカウントID】:domain/slack-hybrid-search/*"
    }
  ]
}
```

---

## まとめ表

| ロール名 | 信頼ポリシー | 管理ポリシー | インラインポリシー |
|---------|------------|------------|------------------|
| `OpenSearchBedrockRole` | `es.amazonaws.com` | なし | `BedrockInvokeModelPolicy` |
| `SlackHybridSearchLambdaRole` | `lambda.amazonaws.com` | `AWSLambdaBasicExecutionRole` | `LambdaExecutionPolicy` |

---

## ポリシー用途一覧

| ポリシー名 | 種類 | 対象ロール | 用途 |
|-----------|------|-----------|------|
| `BedrockInvokeModelPolicy` | インライン | `OpenSearchBedrockRole` | OpenSearchがBedrockでテキストをベクトル化（インジェスト時・検索時） |
| `AWSLambdaBasicExecutionRole` | AWS管理 | `SlackHybridSearchLambdaRole` | Lambda関数の基本実行権限（ログ出力） |
| `LambdaExecutionPolicy` | インライン | `SlackHybridSearchLambdaRole` | OpenSearch Serviceへのアクセス |

---

## AI Connectors使用時のアーキテクチャ上のメリット

AI Connectors（Neural Search）を使用することで、以下のメリットがあります：

| 項目 | 従来方式 | AI Connectors使用時 |
|------|---------|-------------------|
| クエリのベクトル化 | Lambda → Bedrock | OpenSearch内部で自動実行 |
| Lambda の Bedrock 権限 | 必要 | **不要** |
| Lambda のコード | Bedrock呼び出しコードが必要 | シンプル（テキストを渡すだけ） |
| レイテンシ | Lambda→Bedrock→OpenSearchの2ホップ | Lambda→OpenSearchの1ホップ |
| コスト | Lambda実行時間が長い | Lambda実行時間が短縮 |

---

## CDK での実装

本リポジトリでは、上記のIAMロール・ポリシーをCDKで定義しています。

参照: `cdk/lib/slack-hybrid-search-stack.ts`

```typescript
// OpenSearchBedrockRole
const openSearchBedrockRole = new iam.Role(this, 'OpenSearchBedrockRole', {
  roleName: 'OpenSearchBedrockRole',
  assumedBy: new iam.ServicePrincipal('es.amazonaws.com'),
  inlinePolicies: {
    BedrockInvokeModelPolicy: new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['bedrock:InvokeModel'],
          resources: [
            `arn:aws:bedrock:${this.region}::foundation-model/amazon.titan-embed-text-v2:0`,
          ],
        }),
      ],
    }),
  },
});

// SlackHybridSearchLambdaRole
const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
  roleName: 'SlackHybridSearchLambdaRole',
  assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
  managedPolicies: [
    iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
  ],
  inlinePolicies: {
    LambdaExecutionPolicy: new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'es:ESHttpGet',
            'es:ESHttpPost',
            'es:ESHttpPut',
            'es:ESHttpDelete',
            'es:ESHttpHead',
          ],
          resources: [`${domain.domainArn}/*`],
        }),
      ],
    }),
  },
});

// Domain Access Policy
domain.addAccessPolicies(
  new iam.PolicyStatement({
    effect: iam.Effect.ALLOW,
    principals: [
      new iam.ArnPrincipal(lambdaRole.roleArn),
      new iam.ArnPrincipal(openSearchBedrockRole.roleArn),
      // 管理者アクセス用（Workflow API実行用）
      new iam.ArnPrincipal(`arn:aws:iam::${this.account}:role/【管理者ロール名】`),
    ],
    actions: ['es:*'],
    resources: [`${domain.domainArn}/*`],
  })
);
```
