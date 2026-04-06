# Slack Hybrid Search Workflow

Sample code for building a hybrid search system using OpenSearch Serverless AI Connectors with Workflow API.

> **Note**: This repository contains the sample code for the blog post "[OpenSearch Serverless] Building a Hybrid Search System with AI Connectors using Workflow API".

## Overview

This project enables hybrid search on Slack messages by combining keyword search (BM25) and vector search (k-NN) using OpenSearch Serverless.

### Features

- **Hybrid Search**: Search by both keyword matching and semantic similarity
- **Workflow API**: Create all resources in a single API call
- **Serverless**: Fully managed services, no EC2 required
- **Japanese Support**: Japanese language embeddings via Amazon Titan Embeddings V2

## Architecture

![](images/ingest.png)

![](images/search.png)

## Prerequisites

- AWS CLI configured
- Node.js 18.x or later
- pnpm
- Docker (recommended for Lambda Layer build)
- Amazon Bedrock Titan Embeddings V2 enabled

## Quick Start

### 1. CDK Deploy

```bash
# Clone the repository
git clone https://github.com/furuya02/slack-hybrid-search-workflow.git
cd slack-hybrid-search-workflow

# Configure environment variables
cp .env.example .env
# Edit .env with your AWS credentials

# CDK deploy
cd cdk
pnpm install
pnpm cdk bootstrap  # First time only
pnpm cdk deploy
```

After deployment, set the output `CollectionEndpoint` and `BedrockRoleArn` in `.env`.

### 2. Create Hybrid Search Resources (Workflow API)

Create all resources in a single API call using OpenSearch Flow Framework.

```bash
cd ..
./scripts/setup-workflow-api.sh
```

> **Note**: For the individual API approach, see `setup-hybrid-search.sh`.

### 3. Test with Sample Data

Load Slack-style sample data (100 messages) and try hybrid search.

```bash
# Load sample data to OpenSearch
./scripts/load-sample-data.sh
```

After loading, test the search API:

```bash
# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name SlackHybridSearchStack \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
    --output text)

# Test hybrid search
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "Lambda is slow", "mode": "hybrid"}'

# Keyword search
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "cost reduction", "mode": "keyword"}'

# Vector search (semantic similarity)
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "I want to improve performance", "mode": "vector"}'
```

## Search Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `hybrid` | BM25 + k-NN combined | General search (recommended) |
| `keyword` | BM25 only | Technical terms, proper nouns |
| `vector` | k-NN only | Semantic similarity, vague expressions |

## Cost Management

### Estimated Costs (24/7 operation)

| Service | Breakdown | Per Day |
|---------|-----------|---------|
| OpenSearch Serverless | 0.5 OCU x 2 x $0.24/h | ~$5.76 |
| Bedrock Titan | Usage-based | ~$0.01 |
| Lambda + API Gateway | Within free tier | $0.00 |

**Total: ~$5.77/day = ~$40/week**

### Delete Resources

```bash
# Delete all resources after testing
./scripts/cleanup.sh
```

> **Important**: OpenSearch Serverless does not have a pause feature.
> You must delete the collection to stop charges.

## Directory Structure

```
slack-hybrid-search-workflow/
├── cdk/                          # CDK infrastructure code
│   ├── bin/
│   │   └── cdk.ts
│   ├── lib/
│   │   └── slack-hybrid-search-stack.ts
│   └── lambda/
│       ├── slack_webhook/        # Slack event handler
│       │   ├── handler.py
│       │   └── requirements.txt
│       └── search/               # Search API
│           ├── handler.py
│           └── requirements.txt
├── scripts/
│   ├── setup-workflow-api.sh     # Setup using Workflow API (recommended)
│   ├── workflow-template.json    # Workflow definition template
│   ├── setup-hybrid-search.sh    # Setup using individual APIs (reference)
│   ├── load-sample-data.sh       # Load sample data
│   └── cleanup.sh                # Delete resources
├── images/                       # Architecture diagrams
├── README.md
└── README.ja.md
```

## Troubleshooting

### No Search Results

- Confirm workflow setup is complete
- Verify documents are indexed
- Check index status in OpenSearch Dashboards

### Vector Search Not Working

- Verify Bedrock Titan Embeddings V2 is enabled
- Check IAM role has Bedrock permissions

## (Reference) Actual Slack Integration

To connect with your actual Slack workspace, follow these steps:

1. Create a new app at https://api.slack.com/apps
2. In **OAuth & Permissions**, add these scopes:
   - `channels:history` - Read channel messages
   - `channels:read` - Read channel info
3. Enable **Event Subscriptions**
4. Set Request URL to the `SlackWebhookUrl` from CDK outputs
5. In **Subscribe to bot events**, add `message.channels`
6. Install the app to your workspace

## License

MIT
