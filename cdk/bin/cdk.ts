#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib/core';
import { SlackHybridSearchStack } from '../lib/slack-hybrid-search-stack';

const app = new cdk.App();

new SlackHybridSearchStack(app, 'SlackHybridSearchStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'ap-northeast-1',
  },
  description: 'Slack Hybrid Search with OpenSearch Serverless and Bedrock',
});
