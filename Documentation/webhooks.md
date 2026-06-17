# Webhooks

Jared provides a webhook API which allows you to be notified of messages being sent/received. You can reply inline to the webhook requests to respond (command mode), or make separate requests to the [REST API](restapi.md). You can use a site like https://webhook.site/ to debug and view webhook content.

For a step-by-step guide to using webhooks with n8n, see [n8n.md](n8n.md).

## Configuration

Add webhook entries to the `webhooks` array in `config.json` (`~/Library/Application Support/Jared/config.json`).

### RichWebhook schema

```json
{
  "url": "http://localhost:5678/webhook/YOUR-WORKFLOW-ID",
  "mode": "notify",
  "auth": { "secret": "optional-hmac-secret" },
  "deliveryPolicy": { "timeoutSeconds": 10 },
  "failurePolicy": { "maxRetries": 3 },
  "routes": []
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `url` | string | required | Webhook endpoint URL |
| `mode` | `"notify"` \| `"command"` | `"notify"` | Delivery mode (see below) |
| `auth.secret` | string | `null` | HMAC-SHA256 shared secret; bootstraps Keychain on first load |
| `deliveryPolicy.timeoutSeconds` | number | `10` | Per-request timeout in seconds |
| `failurePolicy.maxRetries` | number | `3` | Retries on 5xx or network error (ignored in command mode) |
| `routes` | array | `null` | Route filters; absent or `null` = fires on every message |

### Delivery modes

**`notify` (default)** — fire-and-forget. The response body is ignored. Jared retries up to `maxRetries` times on 5xx or network failures with exponential backoff (1 s, 2 s, 4 s). 4xx errors are not retried.

**`command`** — the response body is sent back as an iMessage reply. Jared never retries command-mode webhooks to prevent duplicate replies.

### Webhook types

**Global webhook** — fires for every message (omit `routes` or set it to `null`/`[]`):

```json
{ "url": "http://localhost:5678/webhook/GLOBAL", "mode": "notify" }
```

**Route webhook** — fires only for messages that match the specified routes. Route-based webhooks do not fire from `didProcess`; they fire via the route callback instead.

```json
{
  "url": "http://localhost:5678/webhook/COMMANDS",
  "mode": "command",
  "routes": [
    {
      "name": "/hello",
      "description": "a test route",
      "parameterSyntax": "/hello",
      "comparisons": { "startsWith": ["/hello"] }
    }
  ]
}
```

### Disabling built-in commands

Add a `disabledCommands` map to `config.json` to prevent specific slash commands from being routed:

```json
{
  "disabledCommands": {
    "/remote": true
  }
}
```

Keys are lowercased command names (e.g. `"/ping"`, `"/send"`). A value of `true` disables that command; `false` or absent leaves it enabled.

**Legacy `routes` key** — configs using the old `"routes": { "name": { "disabled": true } }` format continue to load correctly. The decoder maps legacy entries to `disabledCommands` automatically.

### Backward compatibility

The simple format from Jared v1.6.x loads unchanged. All new fields have defaults:

```json
{ "url": "https://your.webhook.url" }
```

### Request headers

Every delivery includes these headers:

| Header | Value |
|---|---|
| `Content-Type` | `application/json; charset=utf-8` |
| `X-Jared-Delivery-Id` | UUID unique to this delivery attempt |
| `X-Jared-Webhook-Id` | Webhook URL (identifies which webhook fired) |
| `X-Jared-Signature` | `sha256=<hex>` HMAC-SHA256 of the body (only when auth is configured) |

---

## Webhook request body

When a webhook is triggered, the body of the POST request is in the following format.

*outgoing message*
```json
{
  "body": { "message": "Jared is an amazing app" },
  "sendStyle": "regular",
  "attachments": [],
  "recipient": { "handle": "+14256667777", "givenName": "Zeke", "isMe": true },
  "sender": { "handle": "taylor@swift.com", "givenName": "Taylor", "isMe": false },
  "date": "2019-02-03T22:05:05.000Z",
  "guid": "EA123B39-7A45-40D9-BF04-A748B3148695"
}
```

*incoming message*
```json
{
  "body": { "message": "thank u next" },
  "sendStyle": "regular",
  "attachments": [],
  "recipient": { "handle": "ariana@grande.com", "givenName": "Ariana", "isMe": false },
  "sender": { "handle": "zeke@swift.com", "givenName": "Zeke", "isMe": true },
  "date": "2019-02-03T22:05:05.000Z",
  "guid": "EA123B39-7A45-40D9-BF04-A748B3148614"
}
```

---

## Webhook response (command mode)

When `mode` is `"command"`, Jared waits up to `timeoutSeconds` for a response and sends the `body.message` back as an iMessage reply.

*success response*
```json
{
  "success": true,
  "body": { "message": "We're on each other's team" }
}
```

*error response* (Jared logs the error, no reply sent)
```json
{
  "success": false,
  "error": "Too many concurrent requests"
}
```

---

## Sending other messages

If you wish to send messages asynchronously (outside the request-response window), use Jared's [REST API](restapi.md).
