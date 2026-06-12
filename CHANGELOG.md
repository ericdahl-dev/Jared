# Changelog

## v1.7.0 (unreleased)

### Webhook improvements

- **RichWebhook type** — webhooks now support `mode`, `auth`, `deliveryPolicy`, and `failurePolicy` fields in addition to the existing `url` and `routes`. All new fields have sensible defaults; the existing `{url, routes}` format from v1.6.x loads unchanged.
- **Delivery modes** — `mode: notify` (default) for fire-and-forget automation; `mode: command` for workflows that reply to the message sender. Command mode never retries to prevent duplicate iMessage replies.
- **HMAC-SHA256 signing** — set `auth.secret` in config.json (bootstraps macOS Keychain) to add an `X-Jared-Signature` header to every delivery. A loud warning is logged if auth is configured but the secret is missing from Keychain.
- **Retry logic** — notify-mode webhooks retry up to 3 times on 5xx or network errors with 1 s / 2 s / 4 s exponential backoff. 4xx errors are not retried.
- **Concurrency cap** — at most 5 webhooks deliver concurrently per message burst.
- **Request headers** — every delivery now includes `X-Jared-Delivery-Id` (UUID) and `X-Jared-Webhook-Id` (webhook URL) for tracing and deduplication.
- **Structured logging** — webhook delivery events are logged via `os.log` (subsystem: `com.zekesnider.jared`, category: `webhooks`) and are visible in Console.app without enabling Info Messages.
- **n8n integration guide** — see `Documentation/n8n.md` for step-by-step setup, HMAC verification snippet, Docker networking, self-test command, and troubleshooting.

### Bug fixes

- Fixed a loop bug in `WebHookManager.didProcess` where a `break` statement caused all subsequent webhooks to be silently skipped once a routed webhook was encountered. Changed to `continue` so global webhooks after a routed webhook still fire.
- Fixed nil-routes guard: `webhook.routes?.count == 0` returned `false` when routes was nil, incorrectly treating nil as non-empty. Now uses `(webhook.routes ?? []).isEmpty`.

### Configuration

- `config.json` parse errors now log an actionable message including the file path and a link to https://jsonlint.com.
- The default `config.json` created on first launch includes a `_webhooks_example` block showing the full RichWebhook format.

---

## Compatibility

The `{url, routes}` webhook format from v1.6.x is supported indefinitely and loads unchanged. No migration is required.
