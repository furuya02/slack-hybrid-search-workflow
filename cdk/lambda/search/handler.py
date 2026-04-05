"""
ハイブリッド検索 API ハンドラー

このLambda関数は以下の機能を提供します：
1. OpenSearch Serverlessに対するハイブリッド検索（BM25 + k-NN）
2. 3つの検索モード（hybrid/keyword/vector）をサポート
3. AI Connectors（Neural Search）を活用してOpenSearch側でクエリをベクトル化
4. GET/POST両方のHTTPメソッドに対応

Note:
    AI Connectorsを活用することで、Lambda側でBedrockを呼び出す必要がなく、
    OpenSearchが直接Bedrockと連携してクエリをベクトル化します。
"""
import json
import os
import logging
from typing import Any

from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import boto3

# ロギングの設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ============================================================
# 環境変数の読み込み
# ============================================================
OPENSEARCH_ENDPOINT = os.environ.get('OPENSEARCH_ENDPOINT', '')  # OpenSearch Serverlessエンドポイント
INDEX_NAME = os.environ.get('INDEX_NAME', 'slack-messages')       # 検索対象インデックス
SEARCH_PIPELINE = os.environ.get('SEARCH_PIPELINE', 'hybrid-search-pipeline')  # スコア正規化パイプライン
MODEL_ID = os.environ.get('MODEL_ID', '')                         # AI ConnectorのモデルID
AWS_REGION = os.environ.get('AWS_REGION', 'ap-northeast-1')       # AWSリージョン


def get_opensearch_client() -> OpenSearch:
    """
    OpenSearch Serverlessクライアントを作成する

    AWS SigV4認証を使用してOpenSearch Serverlessに接続します。

    Returns:
        OpenSearch: 認証済みのOpenSearchクライアントインスタンス
    """
    service = 'aoss'  # OpenSearch Serverlessのサービス識別子
    credentials = boto3.Session().get_credentials()

    # AWS SigV4認証オブジェクトを作成
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        AWS_REGION,
        service,
        session_token=credentials.token
    )

    # エンドポイントURLからホスト名を抽出
    host = OPENSEARCH_ENDPOINT.replace('https://', '').replace('http://', '')

    return OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=30,
    )


def hybrid_search(
    client: OpenSearch,
    query_text: str,
    size: int = 10,
    search_mode: str = 'hybrid'
) -> dict[str, Any]:
    """
    ハイブリッド検索を実行する

    検索モードに応じて、キーワード検索、ベクトル検索、
    またはその両方を組み合わせたハイブリッド検索を実行します。

    AI Connectors（Neural Search）を活用し、OpenSearch側でクエリを
    自動的にベクトル化するため、Lambda内でのBedrock呼び出しは不要です。

    Args:
        client: OpenSearchクライアント
        query_text: 検索クエリ文字列
        size: 返却する結果の最大数（デフォルト: 10）
        search_mode: 検索モード（'hybrid', 'keyword', 'vector'）

    Returns:
        dict: OpenSearchの検索レスポンス

    検索モードの詳細:
        - keyword: BM25アルゴリズムによるキーワード検索
                   完全一致や部分一致に強い
        - vector: Neural Searchによるベクトル検索
                  意味的な類似性に基づく検索（OpenSearchがベクトル化）
        - hybrid: 両方を組み合わせ、スコアを正規化して統合
                  BM25 × 0.3 + k-NN × 0.7（search_pipelineで設定）
    """
    # ============================================================
    # キーワード検索モード
    # BM25アルゴリズムによる従来型の全文検索
    # ============================================================
    if search_mode == 'keyword':
        search_query = {
            'size': size,
            'query': {
                'match': {
                    'text': {
                        'query': query_text
                    }
                }
            },
            # 返却するフィールドを指定（ベクトルは除外してレスポンスを軽量化）
            '_source': ['message_id', 'channel_id', 'user_id', 'text', 'timestamp', 'thread_ts']
        }

    # ============================================================
    # ベクトル検索モード（Neural Search）
    # AI Connectorsを活用し、OpenSearch側でクエリをベクトル化
    # Lambda内でBedrock呼び出しは不要
    # ============================================================
    elif search_mode == 'vector':
        search_query = {
            'size': size,
            'query': {
                'neural': {
                    'text_embedding': {
                        'query_text': query_text,  # テキストをそのまま渡す
                        'model_id': MODEL_ID,       # OpenSearchがこのモデルでベクトル化
                        'k': size
                    }
                }
            },
            '_source': ['message_id', 'channel_id', 'user_id', 'text', 'timestamp', 'thread_ts']
        }

    # ============================================================
    # ハイブリッド検索モード（デフォルト）
    # キーワード検索とNeural Searchを組み合わせて最適な結果を返す
    # ============================================================
    else:
        search_query = {
            'size': size,
            'query': {
                'hybrid': {
                    'queries': [
                        # サブクエリ1: BM25キーワード検索
                        {
                            'match': {
                                'text': {
                                    'query': query_text
                                }
                            }
                        },
                        # サブクエリ2: Neural Search（AI Connectorsでベクトル化）
                        {
                            'neural': {
                                'text_embedding': {
                                    'query_text': query_text,  # テキストをそのまま渡す
                                    'model_id': MODEL_ID,       # OpenSearchがベクトル化
                                    'k': size
                                }
                            }
                        }
                    ]
                }
            },
            '_source': ['message_id', 'channel_id', 'user_id', 'text', 'timestamp', 'thread_ts']
        }

    # ハイブリッド検索の場合は検索パイプラインを適用
    # パイプラインがスコアの正規化と重み付け統合を行う
    params = {}
    if search_mode == 'hybrid':
        params['search_pipeline'] = SEARCH_PIPELINE

    return client.search(
        index=INDEX_NAME,
        body=search_query,
        params=params
    )


def format_results(response: dict[str, Any]) -> list[dict[str, Any]]:
    """
    OpenSearchの検索結果をAPI用にフォーマットする

    Args:
        response: OpenSearchの生レスポンス

    Returns:
        list[dict]: 整形された検索結果のリスト
                    各要素にはscore, message_id, text等を含む
    """
    hits = response.get('hits', {}).get('hits', [])
    results = []

    for hit in hits:
        source = hit.get('_source', {})
        results.append({
            'score': hit.get('_score'),           # 検索スコア
            'message_id': source.get('message_id'),
            'channel_id': source.get('channel_id'),
            'user_id': source.get('user_id'),
            'text': source.get('text'),
            'timestamp': source.get('timestamp'),
            'thread_ts': source.get('thread_ts'),
        })

    return results


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Lambda関数のメインエントリーポイント

    API Gateway経由で検索リクエストを処理します。
    GETとPOST両方のHTTPメソッドに対応しています。

    Args:
        event: API Gatewayイベント（Lambdaプロキシ統合形式）
        context: Lambda実行コンテキスト

    Returns:
        dict: API Gatewayレスポンス形式

    使用例:
        GET:  /search?q=検索クエリ&mode=hybrid&size=10
        POST: {"query": "検索クエリ", "mode": "hybrid", "size": 10}
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # デフォルト値の設定
    http_method = event.get('httpMethod', 'POST')
    query_text = ''
    size = 10
    search_mode = 'hybrid'

    # ============================================================
    # GETリクエストの処理
    # クエリパラメータからパラメータを取得
    # ============================================================
    if http_method == 'GET':
        params = event.get('queryStringParameters') or {}
        query_text = params.get('q', '')                    # 検索クエリ
        size = int(params.get('size', 10))                  # 結果件数
        search_mode = params.get('mode', 'hybrid')          # 検索モード

    # ============================================================
    # POSTリクエストの処理
    # リクエストボディ（JSON）からパラメータを取得
    # ============================================================
    else:
        body_str = event.get('body', '{}')
        try:
            body = json.loads(body_str)
            query_text = body.get('query', '')              # 検索クエリ
            size = body.get('size', 10)                     # 結果件数
            search_mode = body.get('mode', 'hybrid')        # 検索モード
        except json.JSONDecodeError:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'      # CORS対応
                },
                'body': json.dumps({'error': 'Invalid JSON'})
            }

    # ============================================================
    # 入力バリデーション
    # ============================================================

    # クエリが空の場合はエラー
    if not query_text:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Query parameter is required'})
        }

    # 無効な検索モードの場合はエラー
    if search_mode not in ['hybrid', 'keyword', 'vector']:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Invalid search mode. Use: hybrid, keyword, or vector'})
        }

    # sizeを1〜100の範囲に制限
    size = min(max(1, size), 100)

    # ============================================================
    # 検索の実行
    # ============================================================
    try:
        client = get_opensearch_client()
        response = hybrid_search(client, query_text, size, search_mode)
        results = format_results(response)

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'query': query_text,
                'mode': search_mode,
                'total': response.get('hits', {}).get('total', {}).get('value', 0),
                'results': results
            })
        }
    except Exception as e:
        logger.error(f"Search error: {e}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
