# Using Jared with n8n

Jared's webhook API makes it easy to connect iMessage to [n8n](https://n8n.io), a self-hosted workflow automation platform. Jared posts every message to your n8n webhook, and optionally sends back a reply if your workflow returns a response body.

**Requirements:** macOS with Jared running, n8n (native or Docker).

---

## Response mode: notify vs. command

| | `notify` (default) | `command` |
|---|---|---|
| **When to use** | Fire-and-forget pipelines, logging, CRMs | Workflows that reply to the user |
| **Retries on failure** | Yes — up to 3× with backoff | Never — duplicate replies would be confusing |
| **Response body** | Ignored | Sent back as an iMessage reply |
| **Config** | `"mode": "notify"` | `"mode": "command"` |

Use `notify` for most n8n automations. Use `command` only when your workflow needs to reply directly to the message sender.

---

## Quick start (≈ 5 minutes)

### Step 1 — Add webhook to `config.json`

Open `~/Library/Application Support/Jared/config.json` and add your n8n webhook URL to the `webhooks` array:

```json
"webhooks": [
  {
    "url": "http://localhost:5678/webhook/YOUR-WORKFLOW-ID",
    "mode": "notify",
    "failurePolicy": { "maxRetries": 3 }
  }
]
```

Replace `YOUR-WORKFLOW-ID` with the path from your n8n Webhook node trigger URL.

### Step 2 — Reload Jared

Either send `/reload` in any iMessage conversation, or click **Reload Plugins** in the Jared menu bar icon.

### Step 3 — Import the starter workflow

In n8n, create a new workflow with a **Webhook** trigger node (HTTP method: POST, path matches your URL). Connect it to whatever automation you want.

---

## Self-test

Run this from your terminal to confirm Jared can reach your webhook:

```sh
curl -X POST http://localhost:3005/message \
  -H "Content-Type: application/json" \
  -d '{"handle": "test", "body": "ping"}'
```

In **Console.app** (filter: Process = Jared, Category = webhooks), you should see:

```
Webhook http://localhost:5678/webhook/YOUR-WORKFLOW-ID: delivered (attempt 1, status 200)
```

If you see a warning or error instead, see [Troubleshooting](#troubleshooting) below.

---

## Networking

### Native n8n

Both Jared and n8n run on your Mac. Use `localhost`:

```json
"url": "http://localhost:5678/webhook/YOUR-WORKFLOW-ID"
```

Jared's REST API (for n8n → iMessage direction): `http://localhost:3005/message`

### Docker n8n

n8n runs inside a Docker container. Docker containers cannot reach `localhost` on your Mac — use `host.docker.internal` instead:

- In your Jared `config.json`, n8n's webhook URL is still `http://localhost:5678/webhook/...` (Jared makes the outbound call from macOS, not from inside Docker, so `localhost` works).
- In n8n (inside Docker), to call Jared's REST API, use: `http://host.docker.internal:3005/message`

---

## HMAC request signing

To verify that webhook requests to your n8n workflow actually came from Jared, enable HMAC-SHA256 signing:

**1. Add an auth block to config.json:**

```json
{
  "url": "http://localhost:5678/webhook/YOUR-WORKFLOW-ID",
  "mode": "notify",
  "auth": { "secret": "your-shared-secret" }
}
```

Jared saves the secret to your Mac's Keychain on first load (service: `com.jared.webhook`, account: webhook URL). The `secret` field in config.json is only used to bootstrap Keychain — you can remove it from the file after the first reload.

**2. Verify in n8n:**

In a Function node, verify the `X-Jared-Signature` header:

```javascript
const crypto = require('crypto');
const secret = 'your-shared-secret';
const body = JSON.stringify($input.body);
const sig = 'sha256=' + crypto.createHmac('sha256', secret).update(body).digest('hex');
if ($input.headers['x-jared-signature'] !== sig) {
  throw new Error('Invalid signature');
}
return $input.all();
```

**If the secret is missing from Keychain,** Jared delivers the request unsigned and logs a warning:
```
Webhook …: auth configured but no Keychain secret found — delivering unsigned
```

---

## Migrating from the old webhook format

The simple `{url, routes}` format from Jared v1.6.x loads unchanged — no migration required. The new fields (`mode`, `auth`, `failurePolicy`, `deliveryPolicy`) all have sensible defaults.

**Old format (still valid):**
```json
{ "url": "https://your.webhook.url" }
```

**New format (full options):**
```json
{
  "url": "https://your.webhook.url",
  "mode": "notify",
  "auth": { "secret": "optional-hmac-secret" },
  "deliveryPolicy": { "timeoutSeconds": 10 },
  "failurePolicy": { "maxRetries": 3 }
}
```

### Field reference

| Field | Type | Default | Description |
|---|---|---|---|
| `url` | string | required | Webhook endpoint URL |
| `mode` | `"notify"` \| `"command"` | `"notify"` | Delivery mode — see table above |
| `routes` | array | `null` (global) | Route filters; `null`/absent = fires for every message |
| `auth.secret` | string | `null` | HMAC-SHA256 shared secret (bootstraps Keychain on load) |
| `deliveryPolicy.timeoutSeconds` | number | `10` | Per-request timeout |
| `failurePolicy.maxRetries` | number | `3` | Max retries on 5xx/network error (ignored in command mode) |

---

## Security note

The Jared REST API has no authentication in v1. It accepts requests from any process on the same machine. Keep Jared's port (default: 3005) firewalled from external network access. REST API authentication is planned for v2 — see [TODOS.md](../TODOS.md) T8.

---

## Troubleshooting

Open **Console.app**, set the filter to **Process = Jared** and **Category = webhooks**.

| Log message | Meaning | Fix |
|---|---|---|
| `Webhook …: delivered (attempt 1, status 200)` | Everything working | — |
| `Webhook …: invalid URL — skipping delivery` | Bad URL in config.json | Check the `url` field for typos |
| `Webhook …: 4xx 404 — not retrying` | n8n workflow path wrong | Verify the webhook path in your n8n Webhook node |
| `Webhook …: request failed on attempt 1: …` | n8n not running / wrong port | Start n8n; check it's on port 5678 (native) or use `host.docker.internal` (Docker) |
| `Webhook …: auth configured but no Keychain secret found — delivering unsigned` | HMAC secret not in Keychain | Add `"auth": { "secret": "..." }` to config.json and reload |
| `Failed to parse config.json: …` | Syntax error in config.json | Validate your JSON at https://jsonlint.com |

For further help, open an issue at [github.com/ZekeSnider/Jared/issues](https://github.com/ZekeSnider/Jared/issues).
