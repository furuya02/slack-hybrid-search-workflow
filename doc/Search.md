# 検索時の処理フロー

## 概要

ハイブリッド検索を実行する際、**Neural Search** によってクエリテキストが自動的にベクトル化され、**Search Pipeline** によってスコアが正規化・統合されます。

## 処理フロー図

```
┌─────────────────┐
│      User       │
└────────┬────────┘
         │ 検索リクエスト
         │ { "query": "会議の議事録", "mode": "hybrid" }
         ▼
┌─────────────────┐
│  API Gateway    │
│   (/search)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Lambda function │
│ (Hybrid Search) │
└────────┬────────┘
         │ Neural Search クエリ送信
         │ { "neural": { "query_text": "会議の議事録" } }
         ▼
┌─────────────────────────────────────────────────────────┐
│  OpenSearch Service                                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Neural Search                                      │  │
│  │   query_text を text_docs 配列に変換              │  │
│  │   { "text_docs": ["会議の議事録"] }               │  │
│  │           │                                        │  │
│  │           ▼                                        │  │
│  │  ┌─────────────────┐                              │  │
│  │  │ Model (deployed)│                              │  │
│  │  │   │             │                              │  │
│  │  │   │ connector_id で接続                        │  │
│  │  │   ▼             │                              │  │
│  │  │ ┌─────────────┐ │                              │  │
│  │  │ │AI Connector │ │                              │  │
│  │  │ │ pre_process │◄── text_docs → inputText 変換 │  │
│  │  │ └──────┬──────┘ │                              │  │
│  │  └────────┼────────┘                              │  │
│  │           │                                        │  │
│  └───────────┼────────────────────────────────────────┘  │
│              │ Bedrock API 呼び出し                      │
└──────────────┼───────────────────────────────────────────┘
               ▼
      ┌─────────────────┐
      │ Amazon Bedrock  │
      │ Titan Embed V2  │
      └────────┬────────┘
               │ ベクトル返却 [0.12, 0.34, ...]
               ▼
┌─────────────────────────────────────────────────────────┐
│  OpenSearch Service                                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ AI Connector                                       │  │
│  │   post_process でベクトルを OpenSearch 形式に変換  │  │
│  └───────────────────────────────────────────────────┘  │
│              │                                           │
│              ▼                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Index (slack-messages)                             │  │
│  │   ハイブリッド検索を実行                           │  │
│  │   ├── BM25 キーワード検索 → スコア                │  │
│  │   └── k-NN ベクトル検索 → スコア                  │  │
│  └───────────────────────────────────────────────────┘  │
│              │                                           │
│              ▼                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Search Pipeline (hybrid-search-pipeline)           │  │
│  │   normalization-processor                          │  │
│  │   ├── min_max 正規化 (0〜1)                       │  │
│  │   └── arithmetic_mean 統合                        │  │
│  │       BM25 × 0.3 + k-NN × 0.7                     │  │
│  └───────────────────────────────────────────────────┘  │
│              │                                           │
│              ▼                                           │
│         検索結果                                         │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─────────────────┐
│ Lambda function │
│   結果を整形    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│      User       │
└─────────────────┘
```

---

## 使用されるリソースの関係

| リソース | Workflow での作成 | 検索時の役割 |
|---------|------------------|-------------|
| AI Connector | `create_connector` | Bedrock への接続定義（認証、URL、**pre/post_process_function**） |
| Model | `register_model` + `deploy_model` | Connector を使用可能な状態にしたもの |
| Index | `create_index` | BM25 キーワード検索 + k-NN ベクトル検索を実行 |
| Search Pipeline | `create_search_pipeline` | スコアの正規化と統合 |

---

## リソース間の依存関係

```
┌─────────────────┐
│  AI Connector   │ ← Bedrock への接続 + pre/post_process_function
└────────┬────────┘
         │ connector_id
         ▼
┌─────────────────┐
│     Model       │ ← Connector を参照（Neural Search で使用）
│   (deployed)    │
└────────┬────────┘
         │ model_id（Lambda 環境変数に設定）
         ▼
┌─────────────────┐
│     Index       │ ← BM25 + k-NN 検索を実行
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Search Pipeline │ ← スコアを正規化・統合
└─────────────────┘
```

---

## 処理の詳細

### 1. Lambda が検索クエリを受信

Lambda 関数（`SlackHybridSearch-Search`）が API Gateway 経由で検索リクエストを受信します。

```python
# cdk/lambda/search/handler.py より
# 検索モードに応じてクエリを構築
if search_mode == 'hybrid':
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
        }
    }
```

### 2. Neural Search がクエリをベクトル化

Neural Search は内部で `query_text` を `text_docs` 配列形式に変換します。

```
入力: { "query_text": "会議の議事録" }
  ↓ OpenSearch 内部変換
中間: { "text_docs": ["会議の議事録"] }
```

### 3. pre_process_function が Bedrock 形式に変換

AI Connector の `pre_process_function` が `text_docs` 配列を Bedrock が期待する `inputText` 文字列に変換します。

```
入力:  { "text_docs": ["会議の議事録"] }
  ↓ pre_process_function (Painless スクリプト)
出力:  { "parameters": { "inputText": "会議の議事録" } }
```

> **重要**: この変換がないと `Some parameter placeholder not filled in payload: inputText` エラーが発生します。詳細は [AI Connector の Pre/Post Process Function](./AI_Connector_PreProcess.md) を参照。

### 4. AI Connector が Bedrock を呼び出し

```json
POST https://bedrock-runtime.ap-northeast-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke
{
  "inputText": "会議の議事録",
  "dimensions": 1024,
  "normalize": true
}
```

### 5. Bedrock がベクトルを返却

```json
{
  "embedding": [0.123, 0.456, ..., 0.789]  // 1024次元
}
```

### 6. post_process_function が OpenSearch 形式に変換

```
入力:  { "embedding": [0.123, 0.456, ...] }
  ↓ post_process_function (Painless スクリプト)
出力:  { "name": "sentence_embedding", "data_type": "FLOAT32", "shape": [1024], "data": [0.123, 0.456, ...] }
```

### 7. ハイブリッド検索を実行

Index に対して 2 つの検索を並行実行します。

| 検索タイプ | 対象フィールド | アルゴリズム |
|-----------|---------------|-------------|
| BM25 キーワード検索 | `text` | TF-IDF ベース |
| k-NN ベクトル検索 | `text_embedding` | HNSW (faiss) |

### 8. Search Pipeline がスコアを統合

```
BM25 スコア: 2.5  → 正規化: 0.8
k-NN スコア: 0.85 → 正規化: 0.6
  ↓ arithmetic_mean (weights: [0.3, 0.7])
最終スコア = 0.8 × 0.3 + 0.6 × 0.7 = 0.66
```

### 9. Lambda が結果を整形して返却

```python
# cdk/lambda/search/handler.py より
def format_results(response: dict[str, Any]) -> list[dict[str, Any]]:
    hits = response.get('hits', {}).get('hits', [])
    results = []
    for hit in hits:
        source = hit.get('_source', {})
        results.append({
            'score': hit.get('_score'),
            'message_id': source.get('message_id'),
            'channel_id': source.get('channel_id'),
            'user_id': source.get('user_id'),
            'text': source.get('text'),
            'timestamp': source.get('timestamp'),
            'thread_ts': source.get('thread_ts'),
        })
    return results
```

**レスポンス例:**
```json
{
  "query": "会議の議事録",
  "mode": "hybrid",
  "total": 15,
  "results": [
    {
      "score": 0.89,
      "message_id": "msg-042",
      "text": "明日の会議の議事録を共有します",
      ...
    }
  ]
}
```

---

## 検索モード

Lambda は 3 つの検索モードをサポートしています。

| モード | クエリタイプ | 使用するリソース | ユースケース |
|--------|------------|-----------------|-------------|
| `hybrid` | `hybrid` | Index + Search Pipeline | 一般的な検索（推奨） |
| `keyword` | `match` | Index のみ | 専門用語、固有名詞 |
| `vector` | `neural` | Index + AI Connector | 意味的類似検索 |

### keyword モード

```python
search_query = {
    'query': {
        'match': {
            'text': {
                'query': query_text
            }
        }
    }
}
```

- AI Connector を使用しない（Bedrock 呼び出しなし）
- pre_process_function は不要

### vector モード

```python
search_query = {
    'query': {
        'neural': {
            'text_embedding': {
                'query_text': query_text,
                'model_id': MODEL_ID,
                'k': size
            }
        }
    }
}
```

- Neural Search を使用
- pre_process_function が**必須**

### hybrid モード（デフォルト）

```python
search_query = {
    'query': {
        'hybrid': {
            'queries': [
                { 'match': { 'text': { 'query': query_text } } },
                { 'neural': { 'text_embedding': { 'query_text': query_text, 'model_id': MODEL_ID, 'k': size } } }
            ]
        }
    }
}
params = {'search_pipeline': SEARCH_PIPELINE}
```

- BM25 + Neural Search を組み合わせ
- Search Pipeline でスコアを統合
- pre_process_function が**必須**

---

## インジェスト時との違い

| 項目 | インジェスト時 | 検索時 |
|------|--------------|--------|
| 処理トリガー | ドキュメント登録 | Neural Search クエリ |
| ベクトル化対象 | `text` フィールド | `query_text` パラメータ |
| 使用するプロセッサ | `text_embedding` | AI Connector 直接呼び出し |
| 入力形式 | 文字列 | `text_docs` 配列 |
| `pre_process_function` | **不要** | **必須** |
| `post_process_function` | 標準関数で可 | **カスタム必須** |

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `cdk/lambda/search/handler.py` | Search Lambda 関数（ハイブリッド検索処理） |
| `scripts/workflow-template.json` | Search Pipeline の定義を含む |
| `doc/Lambda.md` | Lambda 関数の詳細 |
| `doc/Ingest.md` | インジェスト時の処理フロー |
| `doc/AI_Connector_PreProcess.md` | pre/post_process_function の詳細 |
| `doc/workflow-template.md` | Workflow テンプレートの構成 |

---

## 参考リンク

- [OpenSearch Neural Search](https://opensearch.org/docs/latest/search-plugins/neural-search/)
- [OpenSearch Hybrid Search](https://opensearch.org/docs/latest/search-plugins/hybrid-search/)
- [OpenSearch Search Pipelines](https://opensearch.org/docs/latest/search-plugins/search-pipelines/index/)
- [Amazon Bedrock Titan Embeddings](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
