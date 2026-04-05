import * as cdk from 'aws-cdk-lib/core';
import * as opensearchserverless from 'aws-cdk-lib/aws-opensearchserverless';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import * as path from 'path';
import { execSync } from 'child_process';

export class SlackHybridSearchStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const collectionName = 'slack-knowledge-base';

    // ===========================================
    // OpenSearch Serverless Collection
    // ===========================================

    // 暗号化ポリシー
    const encryptionPolicy = new opensearchserverless.CfnSecurityPolicy(this, 'EncryptionPolicy', {
      name: `${collectionName}-encryption`,
      type: 'encryption',
      policy: JSON.stringify({
        Rules: [
          {
            ResourceType: 'collection',
            Resource: [`collection/${collectionName}`],
          },
        ],
        AWSOwnedKey: true,
      }),
    });

    // ネットワークポリシー（パブリックアクセス）
    const networkPolicy = new opensearchserverless.CfnSecurityPolicy(this, 'NetworkPolicy', {
      name: `${collectionName}-network`,
      type: 'network',
      policy: JSON.stringify([
        {
          Rules: [
            {
              ResourceType: 'collection',
              Resource: [`collection/${collectionName}`],
            },
            {
              ResourceType: 'dashboard',
              Resource: [`collection/${collectionName}`],
            },
          ],
          AllowFromPublic: true,
        },
      ]),
    });

    // OpenSearch Serverless コレクション（VectorSearch タイプ）
    // コスト削減設定: 冗長性を無効化（検証環境向け）
    const collection = new opensearchserverless.CfnCollection(this, 'SlackKnowledgeBase', {
      name: collectionName,
      type: 'VECTORSEARCH',
      description: 'Slack messages with hybrid search capability',
      standbyReplicas: 'DISABLED', // 冗長性を無効化（最低2 OCUに削減、本番環境では 'ENABLED' を推奨）
    });

    collection.addDependency(encryptionPolicy);
    collection.addDependency(networkPolicy);

    // ===========================================
    // IAM Role for OpenSearch to access Bedrock
    // ===========================================
    const openSearchBedrockRole = new iam.Role(this, 'OpenSearchBedrockRole', {
      roleName: 'OpenSearchBedrockRole',
      assumedBy: new iam.ServicePrincipal('opensearchservice.amazonaws.com'),
      description: 'Role for OpenSearch to invoke Bedrock models',
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

    // ===========================================
    // Lambda Execution Role
    // ===========================================
    // Note: AI Connectors（Neural Search）を使用するため、Lambda側でBedrockを
    // 呼び出す必要はありません。クエリのベクトル化はOpenSearch内部で自動実行されます。
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: 'SlackHybridSearchLambdaRole',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LambdaExecutionPolicy: new iam.PolicyDocument({
          statements: [
            // OpenSearch Serverless へのアクセス権限
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['aoss:APIAccessAll'],
              resources: [collection.attrArn],
            }),
          ],
        }),
      },
    });

    // ===========================================
    // Data Access Policy for OpenSearch Serverless
    // ===========================================
    const dataAccessPolicy = new opensearchserverless.CfnAccessPolicy(this, 'DataAccessPolicy', {
      name: `${collectionName}-data-access`,
      type: 'data',
      policy: JSON.stringify([
        {
          Rules: [
            {
              ResourceType: 'collection',
              Resource: [`collection/${collectionName}`],
              Permission: [
                'aoss:CreateCollectionItems',
                'aoss:DeleteCollectionItems',
                'aoss:UpdateCollectionItems',
                'aoss:DescribeCollectionItems',
              ],
            },
            {
              ResourceType: 'index',
              Resource: [`index/${collectionName}/*`],
              Permission: [
                'aoss:CreateIndex',
                'aoss:DeleteIndex',
                'aoss:UpdateIndex',
                'aoss:DescribeIndex',
                'aoss:ReadDocument',
                'aoss:WriteDocument',
              ],
            },
          ],
          Principal: [
            lambdaRole.roleArn,
            openSearchBedrockRole.roleArn,
            // 現在のアカウントの管理者アクセス用（Workflow API実行用）
            `arn:aws:iam::${this.account}:root`,
          ],
        },
      ]),
    });

    dataAccessPolicy.addDependency(collection);

    // ===========================================
    // Lambda Functions（ローカルバンドリングで依存ライブラリをインストール、Docker不要）
    // ===========================================

    const slackWebhookLambdaPath = path.join(__dirname, '../lambda/slack_webhook');
    const searchLambdaPath = path.join(__dirname, '../lambda/search');

    // Slack Webhook Lambda
    const slackWebhookLambda = new lambda.Function(this, 'SlackWebhookLambda', {
      functionName: 'SlackHybridSearch-SlackWebhook',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(slackWebhookLambdaPath, {
        bundling: {
          image: lambda.Runtime.PYTHON_3_12.bundlingImage,
          local: {
            tryBundle(outputDir: string) {
              execSync(`pip install -r ${path.join(slackWebhookLambdaPath, 'requirements.txt')} -t ${outputDir} --no-cache-dir`);
              execSync(`cp -r ${slackWebhookLambdaPath}/* ${outputDir}`);
              return true;
            },
          },
        },
      }),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        OPENSEARCH_ENDPOINT: collection.attrCollectionEndpoint,
        INDEX_NAME: 'slack-messages',
        INGEST_PIPELINE: 'slack-ingest-pipeline',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Search Lambda
    const searchLambda = new lambda.Function(this, 'SearchLambda', {
      functionName: 'SlackHybridSearch-Search',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'handler.lambda_handler',
      code: lambda.Code.fromAsset(searchLambdaPath, {
        bundling: {
          image: lambda.Runtime.PYTHON_3_12.bundlingImage,
          local: {
            tryBundle(outputDir: string) {
              execSync(`pip install -r ${path.join(searchLambdaPath, 'requirements.txt')} -t ${outputDir} --no-cache-dir`);
              execSync(`cp -r ${searchLambdaPath}/* ${outputDir}`);
              return true;
            },
          },
        },
      }),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        OPENSEARCH_ENDPOINT: collection.attrCollectionEndpoint,
        INDEX_NAME: 'slack-messages',
        SEARCH_PIPELINE: 'hybrid-search-pipeline',
        // MODEL_ID: Workflow実行後に取得したモデルIDを設定
        // Lambda コンソールで環境変数を追加するか、以下のように設定してから再デプロイ
        // MODEL_ID: 'xxxxxxxx',  // ← Workflow実行後に取得したmodel_idを設定
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // ===========================================
    // API Gateway
    // ===========================================
    const api = new apigateway.RestApi(this, 'SlackHybridSearchApi', {
      restApiName: 'Slack Hybrid Search API',
      description: 'API for Slack webhook and hybrid search',
      deployOptions: {
        stageName: 'prod',
        throttlingBurstLimit: 100,
        throttlingRateLimit: 50,
      },
    });

    // /slack/events - Slack Events API Webhook
    const slackResource = api.root.addResource('slack');
    const eventsResource = slackResource.addResource('events');
    eventsResource.addMethod('POST', new apigateway.LambdaIntegration(slackWebhookLambda));

    // /search - Hybrid Search API
    const searchResource = api.root.addResource('search');
    searchResource.addMethod('POST', new apigateway.LambdaIntegration(searchLambda));
    searchResource.addMethod('GET', new apigateway.LambdaIntegration(searchLambda));

    // ===========================================
    // Outputs
    // ===========================================
    new cdk.CfnOutput(this, 'CollectionEndpoint', {
      value: collection.attrCollectionEndpoint,
      description: 'OpenSearch Serverless Collection Endpoint',
      exportName: 'SlackHybridSearchCollectionEndpoint',
    });

    new cdk.CfnOutput(this, 'CollectionArn', {
      value: collection.attrArn,
      description: 'OpenSearch Serverless Collection ARN',
      exportName: 'SlackHybridSearchCollectionArn',
    });

    new cdk.CfnOutput(this, 'OpenSearchBedrockRoleArn', {
      value: openSearchBedrockRole.roleArn,
      description: 'IAM Role ARN for OpenSearch to access Bedrock',
      exportName: 'OpenSearchBedrockRoleArn',
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway Endpoint',
      exportName: 'SlackHybridSearchApiEndpoint',
    });

    new cdk.CfnOutput(this, 'SlackWebhookUrl', {
      value: `${api.url}slack/events`,
      description: 'URL to configure in Slack Event Subscriptions',
      exportName: 'SlackWebhookUrl',
    });

    new cdk.CfnOutput(this, 'SearchApiUrl', {
      value: `${api.url}search`,
      description: 'Search API URL',
      exportName: 'SearchApiUrl',
    });
  }
}
