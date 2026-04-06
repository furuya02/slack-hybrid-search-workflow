"""
Slack Events API Webhook Handler
Receives Slack events and indexes messages to OpenSearch Service
"""
import json
import os
import hashlib
import hmac
import time
import logging
from typing import Any

import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
OPENSEARCH_ENDPOINT = os.environ.get('OPENSEARCH_ENDPOINT', '')
INDEX_NAME = os.environ.get('INDEX_NAME', 'slack-messages')
INGEST_PIPELINE = os.environ.get('INGEST_PIPELINE', 'slack-ingest-pipeline')
SLACK_SIGNING_SECRET = os.environ.get('SLACK_SIGNING_SECRET', '')


def get_opensearch_client() -> OpenSearch:
    """Create OpenSearch client with AWS SigV4 authentication."""
    region = os.environ.get('AWS_REGION', 'ap-northeast-1')
    service = 'es'
    credentials = boto3.Session().get_credentials()

    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        service,
        session_token=credentials.token
    )

    # Extract host from endpoint URL
    host = OPENSEARCH_ENDPOINT.replace('https://', '').replace('http://', '')

    return OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=30,
    )


def verify_slack_signature(event: dict[str, Any]) -> bool:
    """Verify that the request came from Slack."""
    if not SLACK_SIGNING_SECRET:
        logger.warning("SLACK_SIGNING_SECRET not set, skipping signature verification")
        return True

    headers = event.get('headers', {})
    # Handle case-insensitive headers
    timestamp = headers.get('X-Slack-Request-Timestamp') or headers.get('x-slack-request-timestamp')
    signature = headers.get('X-Slack-Signature') or headers.get('x-slack-signature')

    if not timestamp or not signature:
        logger.error("Missing Slack headers")
        return False

    # Check timestamp (reject if older than 5 minutes)
    if abs(time.time() - int(timestamp)) > 60 * 5:
        logger.error("Request timestamp is too old")
        return False

    body = event.get('body', '')
    sig_basestring = f"v0:{timestamp}:{body}"

    my_signature = 'v0=' + hmac.new(
        SLACK_SIGNING_SECRET.encode(),
        sig_basestring.encode(),
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(my_signature, signature)


def index_message(client: OpenSearch, document: dict[str, Any]) -> dict[str, Any]:
    """Index a document to OpenSearch with ingest pipeline."""
    try:
        response = client.index(
            index=INDEX_NAME,
            body=document,
            pipeline=INGEST_PIPELINE,
            refresh=True
        )
        logger.info(f"Document indexed successfully: {response.get('_id')}")
        return response
    except Exception as e:
        logger.error(f"Failed to index document: {e}")
        raise


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Lambda handler for Slack Events API.

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        API Gateway response
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Parse body
    body_str = event.get('body', '{}')
    try:
        body = json.loads(body_str)
    except json.JSONDecodeError:
        logger.error("Failed to parse request body")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON'})
        }

    # Handle URL verification (Slack app setup)
    if body.get('type') == 'url_verification':
        logger.info("URL verification request")
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'challenge': body.get('challenge')})
        }

    # Verify Slack signature
    if not verify_slack_signature(event):
        logger.error("Invalid Slack signature")
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'Invalid signature'})
        }

    # Handle event callback
    if body.get('type') == 'event_callback':
        slack_event = body.get('event', {})
        event_type = slack_event.get('type')

        logger.info(f"Processing event type: {event_type}")

        # Handle message events
        if event_type == 'message':
            # Skip bot messages and message changes
            if slack_event.get('bot_id') or slack_event.get('subtype'):
                logger.info("Skipping bot message or message subtype")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'status': 'skipped'})
                }

            # Extract message data
            document = {
                'message_id': slack_event.get('client_msg_id'),
                'channel_id': slack_event.get('channel'),
                'user_id': slack_event.get('user'),
                'text': slack_event.get('text', ''),
                'timestamp': slack_event.get('ts'),
                'thread_ts': slack_event.get('thread_ts'),
                'team_id': body.get('team_id'),
                'event_time': body.get('event_time'),
            }

            # Remove None values
            document = {k: v for k, v in document.items() if v is not None}

            # Skip if no text content
            if not document.get('text'):
                logger.info("Skipping message without text")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'status': 'skipped', 'reason': 'no text'})
                }

            try:
                client = get_opensearch_client()
                index_message(client, document)

                return {
                    'statusCode': 200,
                    'body': json.dumps({'status': 'indexed'})
                }
            except Exception as e:
                logger.error(f"Error indexing message: {e}")
                return {
                    'statusCode': 500,
                    'body': json.dumps({'error': str(e)})
                }

    # Default response
    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'ok'})
    }
