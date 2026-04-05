# Slack Hybrid Search Workflow

Hybrid search system for Slack messages using OpenSearch Serverless + Amazon Bedrock

[日本語版 README はこちら](README.ja.md)

## Overview

This project enables hybrid search on Slack messages by combining keyword search (BM25) and vector search (k-NN) using OpenSearch Serverless and Amazon Bedrock.

### Features

- **Hybrid Search**: Search by both keyword matching and semantic similarity
- **Serverless**: Fully managed services, no EC2 required
- **Cost Optimized**: Delete resources when not testing to minimize costs
- **Multi-language Support**: Japanese language support via Amazon Titan Embeddings V2

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        OpenSearch Serverless                         │
│                                                                      │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│   │ AI Connector│─▶│   Model     │─▶│  Ingest     │                 │
│   │ (Bedrock)   │  │  Register   │  │  Pipeline   │                 │
│   └─────────────┘  └─────────────┘  └─────────────┘                 │
│                                            │                         │
│                                            ▼                         │
│                    ┌─────────────┐  ┌─────────────┐                 │
│                    │   Search    │◀─│    Index    │                 │
│                    │  Pipeline   │  │  (Vector)   │                 │
│                    └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────┐     ┌─────────────┐
│   Slack     │────▶│ API Gateway │
│ Events API  │     │  + Lambda   │
└─────────────┘     └─────────────┘
```

## Prerequisites

- AWS CLI configured
- Node.js 18.x or later
- pnpm
- Docker (recommended for Lambda Layer build)
- Slack workspace admin access
- Amazon Bedrock Titan Embeddings V2 enabled

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/slack-hybrid-search-workflow.git
cd slack-hybrid-search-workflow
```

### 2. Configure Environment Variables

```bash
cp .env.example .env
# Edit .env with your AWS credentials
```

### 3. Deploy CDK Stack

```bash
cd cdk
pnpm install
pnpm cdk bootstrap  # First time only
pnpm cdk deploy
```

### 4. Setup Workflow

After CDK deployment, configure the OpenSearch workflow:

```bash
./scripts/setup-workflow.sh
```

### 5. Test with Sample Data (No Slack Required)

You can test hybrid search with sample data before setting up Slack:

```bash
# Load sample data directly to OpenSearch
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
  -d '{"query": "Lambda が遅い", "mode": "hybrid"}'

# Keyword search
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "コスト削減", "mode": "keyword"}'

# Vector search (semantic similarity)
curl -X POST "${API_ENDPOINT}search" \
  -H "Content-Type: application/json" \
  -d '{"query": "パフォーマンスを改善したい", "mode": "vector"}'
```

### 6. Configure Slack App

To connect with your actual Slack workspace:

1. Create a new app at https://api.slack.com/apps
2. In **OAuth & Permissions**, add these scopes:
   - `channels:history` - Read channel messages
   - `channels:read` - Read channel info
   - `chat:write` - Post messages (for posting dummy data)
3. Enable **Event Subscriptions**
4. Set Request URL to the `SlackWebhookUrl` from CDK outputs
5. In **Subscribe to bot events**, add `message.channels`
6. Install the app to your workspace

### 7. Post Dummy Messages to Slack for Testing

After Slack integration, test indexing with dummy messages:

```bash
# Set in .env
# SLACK_BOT_TOKEN=xoxb-your-bot-token
# SLACK_CHANNEL_ID=C0123456789

# Auto-post dummy messages
./scripts/post-to-slack.sh
```

Alternatively, manually post the content of `scripts/sample-messages.txt` to your Slack channel.

### 8. Test Search

```bash
# GET request
curl "https://your-api-endpoint/prod/search?q=search+query&mode=hybrid"

# POST request
curl -X POST "https://your-api-endpoint/prod/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "search query", "mode": "hybrid", "size": 10}'
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
| OpenSearch Serverless | 0.5 OCU × 2 × $0.24/h | ~$5.76 |
| Bedrock Titan | Usage-based | ~$0.01 |
| Lambda + API Gateway | Within free tier | $0.00 |

**Total: ~$5.77/day = ~$40/week**

### Cost Reduction

```bash
# Check current cost status
./scripts/check-cost.sh

# Delete all resources after testing
./scripts/cleanup.sh
```

> **Important**: OpenSearch Serverless does not have a pause feature.
> You must delete the collection to stop charges.

## Directory Structure

```
slack-hybrid-search-workflow/
├── cdk/                      # CDK infrastructure code
│   ├── bin/
│   │   └── cdk.ts
│   ├── lib/
│   │   └── slack-hybrid-search-stack.ts
│   └── lambda/
│       ├── slack_webhook/    # Slack event handler
│       │   ├── handler.py
│       │   └── requirements.txt
│       └── search/           # Search API
│           ├── handler.py
│           └── requirements.txt
├── scripts/
│   ├── setup-workflow.sh     # Setup Workflow API
│   ├── load-sample-data.sh   # Load sample data (no Slack needed)
│   ├── post-to-slack.sh      # Post dummy messages to Slack
│   ├── sample-messages.txt   # Sample messages list
│   ├── cleanup.sh            # Delete resources
│   └── check-cost.sh         # Check costs
├── README.md
├── README.ja.md
└── memo.md                   # Implementation notes
```

## Troubleshooting

### Slack URL Verification Fails

- Verify the API Gateway endpoint URL is correct
- Check Lambda logs for `challenge` response

### No Search Results

- Confirm workflow setup is complete
- Verify documents are indexed
- Check index status in OpenSearch Dashboards

### Vector Search Not Working

- Verify Bedrock Titan Embeddings V2 is enabled
- Check IAM role has Bedrock permissions

## License

MIT
