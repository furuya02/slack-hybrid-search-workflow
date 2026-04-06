# AI Connector の Pre/Post Process Function

OpenSearch の AI Connector で Bedrock Titan Embeddings V2 を使用する際に必要な、カスタム pre_process_function と post_process_function について説明します。

## 背景

### 発生したエラー

Neural Search（hybrid/vector モード）で検索を実行した際、以下のエラーが発生しました：

```json
{
  "error": "RequestError(400, 'illegal_argument_exception', 'Some parameter placeholder not filled in payload: inputText')"
}
```

### 試した設定と結果

| 設定 | 結果 |
|------|------|
| `pre_process_function` なし | ❌ エラー |
| `connector.pre_process.default.embedding`（標準関数） | ❌ エラー |
| **カスタム Painless スクリプト** | ✅ 成功 |

---

## 原因

### データフローの違い

Neural Search と Bedrock Titan Embeddings では、期待するデータ形式が異なります。

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Neural Search クエリ                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "query": {                                                    │   │
│  │      "neural": {                                                 │   │
│  │        "text_embedding": {                                       │   │
│  │          "query_text": "Lambda が遅い",  ← テキストをそのまま渡す │   │
│  │          "model_id": "xxx",                                      │   │
│  │          "k": 10                                                 │   │
│  │        }                                                         │   │
│  │      }                                                           │   │
│  │    }                                                             │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              ↓                                          │
│                     OpenSearch 内部変換                                  │
│                              ↓                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "text_docs": ["Lambda が遅い"]  ← 配列形式に変換される        │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘

                              ↓ pre_process_function で変換

┌─────────────────────────────────────────────────────────────────────────┐
│  Bedrock Titan Embeddings V2 が期待する形式                              │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  {                                                               │   │
│  │    "inputText": "Lambda が遅い",  ← 文字列形式                   │   │
│  │    "dimensions": 1024,                                           │   │
│  │    "normalize": true                                             │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 問題点

1. **Neural Search** は `text_docs` 配列形式（`["テキスト"]`）でテキストを渡す
2. **Bedrock Titan** は `inputText` 文字列形式（`"テキスト"`）を期待する
3. OpenSearch 標準の `connector.pre_process.default.embedding` ではこの変換がうまく動作しなかった

---

## 解決策

### カスタム Painless スクリプト

`workflow-template.json` の Connector 設定に、カスタムの pre_process_function と post_process_function を追加しました。

#### pre_process_function

Neural Search の入力を Bedrock 形式に変換します。

```painless
StringBuilder builder = new StringBuilder();
builder.append("\"");
String first = params.text_docs[0];    // 配列の最初の要素を取得
builder.append(first);
builder.append("\"");
def parameters = "{" +"\"inputText\":" + builder + "}";
return  "{" +"\"parameters\":" + parameters + "}";
```

**変換内容：**
```
入力:  { "text_docs": ["Lambda が遅い"] }
出力:  { "parameters": { "inputText": "Lambda が遅い" } }
```

#### post_process_function

Bedrock のレスポンスを OpenSearch 形式に変換します。

```painless
def name = "sentence_embedding";
def dataType = "FLOAT32";
if (params.embedding == null || params.embedding.length == 0) {
    return params.message;
}
def shape = [params.embedding.length];
def json = "{" +
           "\"name\":\"" + name + "\"," +
           "\"data_type\":\"" + dataType + "\"," +
           "\"shape\":" + shape + "," +
           "\"data\":" + params.embedding +
           "}";
return json;
```

**変換内容：**
```
入力:  { "embedding": [0.123, 0.456, ...] }
出力:  { "name": "sentence_embedding", "data_type": "FLOAT32", "shape": [1024], "data": [0.123, 0.456, ...] }
```

---

## workflow-template.json での設定

```json
{
  "actions": [{
    "action_type": "predict",
    "method": "POST",
    "url": "https://bedrock-runtime.${AWS_REGION}.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke",
    "request_body": "{ \"inputText\": \"${parameters.inputText}\", \"dimensions\": 1024, \"normalize\": true }",
    "pre_process_function": "\n    StringBuilder builder = new StringBuilder();\n    builder.append(\"\\\"\");\n    String first = params.text_docs[0];\n    builder.append(first);\n    builder.append(\"\\\"\");\n    def parameters = \"{\" +\"\\\"inputText\\\":\" + builder + \"}\";\n    return  \"{\" +\"\\\"parameters\\\":\" + parameters + \"}\";",
    "post_process_function": "\n    def name = \"sentence_embedding\";\n    def dataType = \"FLOAT32\";\n    if (params.embedding == null || params.embedding.length == 0) {\n        return params.message;\n    }\n    def shape = [params.embedding.length];\n    def json = \"{\" +\n               \"\\\"name\\\":\\\"\" + name + \"\\\",\" +\n               \"\\\"data_type\\\":\\\"\" + dataType + \"\\\",\" +\n               \"\\\"shape\\\":\" + shape + \",\" +\n               \"\\\"data\\\":\" + params.embedding +\n               \"}\";\n    return json;"
  }]
}
```

> **Note**: JSON 内で Painless スクリプトを記述するため、エスケープが複雑になっています。

---

## 影響範囲

| 処理 | pre_process_function の必要性 |
|------|------------------------------|
| **Ingest Pipeline（インデックス時）** | 不要（text_embedding プロセッサが直接処理） |
| **Neural Search（検索時）** | **必須**（hybrid/vector モード） |

### 検索モード別の影響

| モード | Neural Search 使用 | pre_process_function |
|--------|-------------------|---------------------|
| `keyword` | ❌ | 不要 |
| `vector` | ✅ | **必須** |
| `hybrid` | ✅ | **必須** |

---

## 個別 API との違い

`setup-hybrid-search.sh`（個別 API 版）では、pre_process_function なしで Connector を作成しています。

```bash
# setup-hybrid-search.sh の Connector 設定
"request_body": "{ \"inputText\": \"${parameters.inputText}\", ... }",
"post_process_function": "connector.post_process.default.embedding"
```

Workflow API と個別 API で動作が異なる可能性があります。検証の結果、Workflow API では**カスタム関数が必須**でした。

---

## 参考リンク

- [OpenSearch ML Commons - Connectors](https://opensearch.org/docs/latest/ml-commons-plugin/remote-models/connectors/)
- [OpenSearch Neural Search](https://opensearch.org/docs/latest/search-plugins/neural-search/)
- [Amazon Bedrock Titan Embeddings](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
