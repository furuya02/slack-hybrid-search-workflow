import * as cdk from 'aws-cdk-lib/core';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';
import * as path from 'path';
import { execSync } from 'child_process';

export class SlackHybridSearchStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const domainName = 'slack-hybrid-search';

    // ===========================================
    // IAM Role for OpenSearch to access Bedrock
    // ===========================================
    const openSearchBedrockRole = new iam.Role(this, 'OpenSearchBedrockRole', {
      roleName: 'OpenSearchBedrockRole',
      assumedBy: new iam.ServicePrincipal('es.amazonaws.com'),
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
    // OpenSearch Service Domain
    // ===========================================
    const domain = new opensearch.Domain(this, 'SlackHybridSearchDomain', {
      domainName: domainName,
      version: opensearch.EngineVersion.OPENSEARCH_2_13,

      // 最小構成（コスト最適化）
      capacity: {
        dataNodes: 1,
        dataNodeInstanceType: 't3.medium.search',
        multiAzWithStandbyEnabled: false,
      },

      // EBS ストレージ
      ebs: {
        volumeSize: 10,
        volumeType: ec2.EbsDeviceVolumeType.GP3,
      },

      // パブリックアクセス（検証用）
      // 本番環境では VPC 内に配置することを推奨

      // ノード間暗号化
      nodeToNodeEncryption: true,
      encryptionAtRest: {
        enabled: true,
      },

      // Fine-grained access control を無効化（シンプルな構成）
      fineGrainedAccessControl: undefined,

      // HTTPS 必須
      enforceHttps: true,

      // ログ
      logging: {
        slowSearchLogEnabled: true,
        slowIndexLogEnabled: true,
        appLogEnabled: true,
      },

      // 削除保護を無効化（検証用）
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ===========================================
    // Lambda Execution Role
    // ===========================================
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: 'SlackHybridSearchLambdaRole',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LambdaExecutionPolicy: new iam.PolicyDocument({
          statements: [
            // OpenSearch Service へのアクセス権限
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

    // ===========================================
    // Domain Access Policy
    // ===========================================
    domain.addAccessPolicies(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [
          new iam.ArnPrincipal(lambdaRole.roleArn),
          new iam.ArnPrincipal(openSearchBedrockRole.roleArn),
          // 管理者アクセス用（Workflow API実行用）
          new iam.ArnPrincipal(`arn:aws:iam::${this.account}:role/cm-hirauchi.shinichi`),
        ],
        actions: ['es:*'],
        resources: [`${domain.domainArn}/*`],
      })
    );

    // ===========================================
    // Lambda Functions
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
        OPENSEARCH_ENDPOINT: domain.domainEndpoint,
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
        OPENSEARCH_ENDPOINT: domain.domainEndpoint,
        INDEX_NAME: 'slack-messages',
        SEARCH_PIPELINE: 'hybrid-search-pipeline',
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
    new cdk.CfnOutput(this, 'DomainEndpoint', {
      value: domain.domainEndpoint,
      description: 'OpenSearch Service Domain Endpoint',
      exportName: 'SlackHybridSearchDomainEndpoint',
    });

    new cdk.CfnOutput(this, 'DomainArn', {
      value: domain.domainArn,
      description: 'OpenSearch Service Domain ARN',
      exportName: 'SlackHybridSearchDomainArn',
    });

    new cdk.CfnOutput(this, 'OpenSearchBedrockRoleArn', {
      value: openSearchBedrockRole.roleArn,
      description: 'IAM Role ARN for OpenSearch to access Bedrock',
      exportName: 'OpenSearchBedrockRoleArn',
    });

    new cdk.CfnOutput(this, 'OpenSearchDashboardsUrl', {
      value: `https://${domain.domainEndpoint}/_dashboards`,
      description: 'OpenSearch Dashboards URL',
      exportName: 'OpenSearchDashboardsUrl',
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
