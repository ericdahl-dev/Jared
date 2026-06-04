# LLM Integration

Jared can forward unrecognised messages to a large language model and reply with the response. This turns any iMessage conversation into an AI chat — any message that isn't a `/command` and isn't rate-limited is automatically sent to the configured LLM.

## How it works

`LLMModule` registers a **catch-all route** that matches any message containing an empty string (i.e. every message). Because Jared evaluates routes in registration order and exact-command routes are registered first, the LLM route only fires when no other route has already handled the message.

The module:
1. Checks the per-sender rate limit (default 10 s). Ignores the message silently if within the limit.
2. Sends the message text to the OpenAI Chat Completions endpoint (`https://api.openai.com/v1/chat/completions`).
3. Replies with the model's response text.

If `apiKey` is empty or the `"llm"` key is missing from `config.json`, the module loads but does nothing.

## Configuration

Add an `"llm"` object to `~/Library/Application Support/Jared/config.json`:

```json
{
  "llm": {
    "provider": "openai",
    "apiKey": "sk-...",
    "model": "gpt-4o",
    "systemPrompt": "You are a helpful assistant.",
    "rateLimitSeconds": 10.0
  }
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `provider` | string | `"openai"` | LLM provider identifier. Currently decoded but only OpenAI is supported. |
| `apiKey` | string | `""` | OpenAI API key. Leave empty to disable LLM replies. |
| `model` | string | `"gpt-4o"` | Model name passed directly to the API (e.g. `gpt-4o`, `gpt-4-turbo`, `gpt-3.5-turbo`). |
| `systemPrompt` | string | `"You are a helpful assistant."` | System message prepended to every conversation. |
| `rateLimitSeconds` | number | `10.0` | Minimum seconds between LLM replies per sender handle. |

See [config-sample.json](config-sample.json) for a full configuration example.

## Rate limiting

Each sender (identified by their iMessage handle) has an independent rate-limit bucket. If a second message arrives from the same sender before `rateLimitSeconds` has elapsed, it is silently ignored. This prevents runaway API usage in active group chats.

## Current limitations

- Only the OpenAI Chat Completions API is supported. The `provider` field is decoded for future use.
- Conversation history is not persisted — each message is sent as a single-turn prompt with only the system prompt prepended.
- There is no per-conversation context; all senders share the same `systemPrompt`.
