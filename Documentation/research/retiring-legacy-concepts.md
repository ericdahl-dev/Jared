# Research: Retiring Legacy Concepts

**Issue:** [#53 — Research retiring legacy concepts](https://github.com/ericdahl-dev/Jared/issues/53)  
**Date:** 2026-06-16  
**Status:** Research complete — recommendations only, no code changes in this document.

## Summary

Jared has three overlapping extension surfaces: **native `.bundle` plugins**, **config-defined routes** (used by webhooks and built-in commands), and **direct LLM integration**. After reviewing the codebase and searching GitHub for real-world plugin usage, the ecosystem picture is clear:

| Concept | Community adoption | Overlap with newer APIs | Retire? |
| --- | --- | --- | --- |
| External plugins (`.bundle`) | Effectively zero | Webhooks + REST API cover the same use cases | **Yes — deprecate external loading** |
| `Route` / `RoutingModule` (internal) | N/A — core architecture | Webhooks already deserialize routes from config | **Keep internally; simplify user-facing model** |
| `config.routes` disable map | Unknown usage | Could fold into per-webhook or per-command flags | **Rework — low value as a global map** |
| Built-in LLM module | New (v1.6+) | Webhook `command` mode + n8n can do the same | **Keep only if invested in properly; otherwise replace with webhook recipe** |

**Recommended direction:** Treat **webhooks (notify + command) + REST API** as the primary extension surface. Keep `Route`/`MessageMatcher` as internal plumbing. Deprecate external plugin loading with a long sunset. Either **substantially improve** LLM (history, providers, Keychain, UX) or **document it as a demo** and point users at webhook-based AI workflows.

---

## 1. Plugins

### What exists today

- `PluginManager` scans `~/Library/Application Support/Jared/Plugins/` for `.bundle` files.
- Each bundle must declare `JaredFrameworkVersion = "J3.0.0"` **exactly** or it is **silently rejected** (`PluginManager.loadBundle`).
- Bundles implement `RoutingModule` from `JaredFramework` and register Swift `Route` handlers.
- `/reload` and **Reload Plugins** in the menu bar unload/reload bundles and re-register internal modules.

Built-in functionality is *also* implemented as `RoutingModule` instances — not as external plugins:

| Module | Role |
| --- | --- |
| `CoreModule` | `/ping`, `/send`, `/whoami`, `/name`, `/barf`, etc. |
| `ScheduleModule` | `/schedule` + Core Data persistence |
| `InternalModule` | `/help`, `/enable`, `/disable`, `/reload` |
| `WebHookManager` | Webhook delivery (global + route-filtered) |
| `LLMModule` | Catch-all LLM fallback |

So "plugins" in documentation means two different things: **external bundles** vs **internal routing modules**. Only the external bundle path is a candidate for retirement.

### GitHub ecosystem search

Searches performed (2026-06-16):

- `JaredFrameworkVersion` in code → hits only `ZekeSnider/Jared`, `ZekeSnider/JaredTwitchPlugin`, and the in-repo sample.
- `RoutingModule` + Jared context → same set.
- `EmoteModule` → only the sample under `Documentation/SampleModule/`.

**Third-party plugins found: 1**

| Repo | Author | Stars | Last push | Notes |
| --- | --- | --- | --- | --- |
| [ZekeSnider/JaredTwitchPlugin](https://github.com/ZekeSnider/JaredTwitchPlugin) | Original Jared author | 1 | 2020-12-04 | Twitch live notifications via embedded HTTP server (Telegraph) on port 8090; `/twitch` and `/roll` commands |

No other published `.bundle` plugins were found. The main readme still says *"If you developed any plugins, please send me a link"* but lists **no community plugins** — consistent with an empty ecosystem.

The in-repo [SampleModule](../SampleModule/) (`EmoteModule`) is documentation only, not a shipped product.

### Why adoption is near zero

1. **High friction:** Xcode project, link `JaredFramework.framework`, match exact framework version string, build `.bundle`, manually install, `/reload`.
2. **Silent failure** on version mismatch — no user-visible error when a plugin is rejected.
3. **Webhooks supersede most plugin use cases** since v1.6+ (route filters, command mode replies) and v1.7 (HMAC, retries, delivery UI).
4. **REST API** covers async outbound messaging that plugins used to implement in-process.
5. **macOS sandboxing / notarization** makes distributing unsigned bundles harder than hitting an HTTP endpoint.

### What JaredTwitchPlugin actually does (migration hint)

The only external plugin:

- Runs an in-process HTTP server for Twitch EventSub-style callbacks.
- Stores subscriber handles in `UserDefaults`.
- Sends iMessages when a stream goes live.

This maps cleanly to **webhook notify mode** + an external service (or n8n workflow) that receives Twitch webhooks and calls Jared's REST API — no `.bundle` required.

### Recommendation: plugins

| Action | Rationale |
| --- | --- |
| **Deprecate external `.bundle` loading** | No meaningful community usage; maintenance cost (framework versioning, `/reload`, docs, sample project). |
| **Keep `JaredFramework` + `RoutingModule` internally** | Built-in commands and `WebHookManager` depend on it; renaming to `CommandModule` / `HandlerModule` is optional cleanup. |
| **Sunset path** | Log a one-time warning when bundles are found → document migration to webhooks → remove loader in a major version. |
| **Preserve `/reload`** | Still needed to hot-reload `config.json` webhooks; rename UI copy from "Reload Plugins" to "Reload Configuration". |
| **Archive or rewrite JaredTwitchPlugin** | Point to n8n/Twitch + Jared webhook docs as the replacement. |

**Do not remove** the internal module pattern without a larger rewrite — it's how every built-in command works today.

---

## 2. Routes

### What "routes" means in Jared (three layers)

1. **`Route` struct** (`JaredFramework/Route.swift`) — name, `comparisons` map (`startsWith`, `contains`, `is`, `containsURL`, `isReaction`), optional `call` closure.
2. **`Router`** — iterates all routes from all modules, uses `MessageMatcher`, invokes `route.call(message)` on match. Also notifies `MessageDelegate`s first (webhook global notify).
3. **`config.routes`** — **only** a disable list: `{ "routename": { "disabled": true } }`. Not a route definition file.

Webhook config **also** embeds `Route`-shaped JSON (without `call` — `WebHookManager.updateHooks` injects the closure at load time).

### Current message flow

```
DatabaseHandler
  → Router.route(message)
      → MessageDelegate.didProcess (global webhooks: routes nil/empty)
      → for each Route in getAllRoutes():
            if enabled(routeName) && MessageMatcher.matches:
                route.call(message)
```

Webhook routes and native routes share the same matcher and registration list (`WebHookManager.routes` is flattened into `getAllRoutes()`).

### Overlap with webhooks

| Capability | Native plugin route | Webhook route | Webhook global notify |
| --- | --- | --- | --- |
| Filter by message text | Yes | Yes (`comparisons`) | No (all messages) |
| Reply inline | Yes (`MessageSender`) | Yes (`mode: command`) | No |
| External logic | Swift in-process | Any HTTP service | Any HTTP service |
| Disable via config | `config.routes` | Per-webhook `enabled` (UI) | Per-webhook `enabled` |
| Retry / HMAC / delivery log | No | Yes (notify mode) | Yes |

**User-facing "routes" as a separate concept from webhooks is redundant.** Webhooks already *are* route definitions plus an HTTP endpoint. The [routes.md](../routes.md) doc presents plugins and webhooks as peers; in practice webhooks won.

### What cannot be removed

- **`Route` + `MessageMatcher`** — required for built-in `/commands`, LLM catch-all, and webhook filtering.
- **Route registration order** — `LLMModule` relies on being registered after command routes so its `.contains: [""]` catch-all only fires for unmatched messages.

### Recommendation: routes

| Action | Rationale |
| --- | --- |
| **Stop documenting "routes" as a standalone extension API** | Merge mental model: webhooks have optional **filters** (today's `routes` array). |
| **Rename in config/docs (optional)** | `webhooks[].routes` → `webhooks[].filters` or `triggers` to reduce confusion with `config.routes`. |
| **Rework `config.routes` disable map** | Either per-filter `disabled` on webhook entries, or `disabledCommands: ["/send"]` for built-ins only. The current global map is easy to misconfigure (must match `route.name` case-insensitively). |
| **Keep built-in Swift commands** | `/ping`, `/schedule`, etc. need in-process handlers unless every command moves to webhook command mode (high latency, worse UX for simple builtins). |

### Possible end state

```
Extensions (user-facing):
  webhooks[]     → notify | command, optional filters, auth, retries
  webServer      → REST POST /message for async outbound
  llm?           → optional first-party AI (if kept)

Internal only:
  Route, MessageMatcher, RoutingModule
  CoreModule, ScheduleModule, InternalModule
```

---

## 3. Direct LLM integration

### What exists today (`LLMModule`)

- Loaded when `config.llm` is present (`PluginManager.addInternalModules`).
- Registers catch-all route: `comparisons: [.contains: [""]]` — matches every text message.
- Skips: disabled via `UserDefaults` `LLMIsDisabled`, slash-prefixed commands, empty `apiKey`.
- Per-sender rate limit (`rateLimitSeconds`, default 10s) — **silently drops** excess messages.
- Single-turn OpenAI Chat Completions call; `provider` field is decoded but **ignored** (hardcoded OpenAI URL).
- No conversation memory, no per-chat system prompt, no attachment handling.
- API key stored in **plaintext** `config.json` (webhooks use Keychain for secrets; LLM does not).
- Settings UI: `LLMSettingsViewController` (API key, model, system prompt, rate limit).
- Tests: reply parsing, slash skip, rate limit, graceful API failure (`LLMModuleTests`).

### Why it feels "not actually useful"

| Gap | User impact |
| --- | --- |
| No multi-turn context | Every message is isolated; feels like a bad ChatGPT wrapper |
| Silent rate limiting | Users think Jared ignored them |
| Silent API failures | No "sorry, LLM unavailable" reply |
| OpenAI-only | `provider` field is misleading |
| Catch-all route | Fires for **all** non-command chats when enabled — no per-contact opt-in |
| Plaintext API key | Security inconsistency vs webhook HMAC secrets |
| Competes with webhooks | n8n + OpenAI node + `command` mode is more flexible |

### Webhook alternative (already supported)

A production-grade AI assistant over iMessage today:

1. Global or filtered webhook → n8n / custom server.
2. Server calls OpenAI (or any model), maintains session history in DB.
3. Return `{ "success": true, "body": { "message": "..." } }` in **command** mode for inline reply.
4. Use REST API for proactive messages.

v1.7 webhook features (HMAC, delivery log, retries, management UI) make this path strictly better for anything beyond a demo.

### Recommendation: LLM

**Option A — Invest (if first-party AI chat is a product goal)**

| Feature | Priority |
| --- | --- |
| Per-chat or per-sender conversation history (Core Data or file-backed) | High |
| Store API key in Keychain | High |
| User-visible errors ("rate limited", "API error") | High |
| Per-contact enable list / `/llm on` command | High |
| Honor `provider` (Anthropic, local Ollama, OpenAI-compatible base URL) | Medium |
| Remove catch-all hack; explicit `/ask` route or opt-in flag | Medium |
| Streaming responses (chunked send) | Low |

**Option B — Retire built-in LLM (if webhooks are the strategic surface)**

- Remove `LLMModule` and settings UI.
- Ship an [n8n.md](../n8n.md)-style **"LLM over iMessage"** recipe using command-mode webhooks.
- Keep `Documentation/llm.md` as migration guide for one release, then delete.

**Suggested default:** **Option B** unless there is explicit appetite to maintain a first-class AI product inside Jared. The webhook stack just received major investment (v1.7); duplicating orchestration in Swift fights that direction.

---

## 4. Cross-cutting concerns

### Naming debt

| Today | Problem | Suggested |
| --- | --- | --- |
| `PluginManager` | Manages webhooks + builtins + bundles | `ModuleRegistry` or `RouteRegistry` |
| "Reload Plugins" | Reloads config, not just bundles | "Reload Configuration" |
| `config.routes` | Sounds like route definitions | `disabledCommands` or fold into webhook config |
| `RoutingModule` | Sounds plugin-specific | `CommandModule` (internal) |

### Documentation to update (when implementing)

- [readme.md](../../readme.md) — Extensions section still centers plugins.
- [plugins.md](../plugins.md) — deprecate or archive.
- [routes.md](../routes.md) — fold into [webhooks.md](../webhooks.md).
- [AGENTS.md](../../AGENTS.md) — plugin system section.
- [llm.md](../llm.md) — either expand with Option A spec or add deprecation notice.

### Risk matrix

| Change | Risk | Mitigation |
| --- | --- | --- |
| Remove bundle loader | Low — no known users beyond author's 2020 plugin | Deprecation warning for 1–2 releases |
| Rename config fields | Medium — breaks existing configs | Decoder aliases for old keys |
| Remove LLM module | Medium — users on v1.6+ may rely on it | Migration doc + n8n template |
| Move builtins to webhooks | High — latency, offline, AppleScript timing | Do not pursue short-term |

---

## 5. Proposed phased plan

### Phase 1 — Documentation & telemetry (low risk)

- Add deprecation notice to `plugins.md`.
- Log when a `.bundle` is loaded (count, name) and when version check fails (currently silent).
- Rename menu item "Reload Plugins" → "Reload Configuration".
- Comment on #53 with this research; link from issue.

### Phase 2 — Consolidate user-facing model

- Merge `routes.md` into `webhooks.md`; document filters/triggers terminology.
- Replace `config.routes` with clearer disable mechanism.
- Add n8n "OpenAI assistant" starter workflow to docs.

### Phase 3 — Remove external plugins

- Stop scanning `Plugins/` folder (or warn-only release first).
- Remove `Documentation/SampleModule` or move to `archive/`.
- Archive JaredTwitchPlugin with README pointing to webhook migration.

### Phase 4 — LLM decision

- **If keep:** implement Option A minimum viable (Keychain, history, opt-in, errors).
- **If drop:** remove `LLMModule`, settings UI, tests; ship webhook recipe.

---

## 6. Conclusion

The issue's intuition is correct:

1. **Plugins** — safe to retire as an *external* extension mechanism; almost nobody uses them.
2. **Routes** — rework the *user-facing* model into webhooks/filters; keep `Route` as internal matcher glue.
3. **LLM** — not useful enough today; either fund a serious build-out or defer to webhook + external AI orchestration.

The strategic end state is **"iMessage bridge + webhook/REST automation platform"** with a small set of built-in slash commands, not **"Swift plugin host with three competing extension APIs."**

---

## Appendix: Search methodology

- GitHub CLI code search: `JaredFrameworkVersion`, `RoutingModule`, `EmoteModule`.
- GitHub API: [ZekeSnider/JaredTwitchPlugin](https://github.com/ZekeSnider/JaredTwitchPlugin) metadata.
- Codebase review: `PluginManager`, `Router`, `WebHookManager`, `LLMModule`, `Route`, `config-sample.json`, tests.
- Issue history on upstream: #9 (plugin loading), #41 (webhook routes), #95 (LLM), #96 (RichWebhook).
