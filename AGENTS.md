# AGENTS.md — Jared iMessage Bot

## Build & Test

**Build/run**: Open `Jared.xcodeproj` in Xcode. There are four schemes:
- `JaredUI` — the main macOS app
- `JaredFramework` — the shared framework (build this first if JaredFramework module errors appear)
- `JaredTests` — unit tests
- `JaredUITests` — UI tests

**Run tests from CLI** (as used in CI):
```
xcodebuild -project Jared.xcodeproj -scheme JaredTests test ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Or run the CI script (builds `JaredFramework` first):
```
bash ./.github/scripts/test-macos.sh
```

**GitHub Actions** (`.github/workflows/test.yml`): macOS unit tests run on a **self-hosted** runner only when the repository variable `MACOS_CI_ENABLED` is `true` (Settings → Secrets and variables → Actions → Variables). The runner must have labels `self-hosted` and `macOS`. When the variable is unset or not `true`, the job is skipped — flip it on when your Mac runner is online.

**Release** (`.github/workflows/release.yml`): triggers on `v*` tags or **workflow_dispatch**. Builds on the same self-hosted Mac when `MACOS_CI_ENABLED` is `true` (always runs on manual dispatch). Script: `bash ./.github/scripts/release-macos.sh` (archive → export → optional notarize → zip). Uploads a draft GitHub release with `Jared-<version>.zip`.

Optional repository **secrets** for signing/notarization: `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`, `MACOS_CODESIGN_IDENTITY`. Notarization uses keychain profile `notarytool` (or creates it from those secrets). Without Apple secrets, export still runs if Developer ID is in the runner keychain; notarization is skipped.

**"No such module 'JaredFramework'" errors**: This is normal when Xcode hasn't built the framework target yet. Build the `JaredFramework` scheme first, then build `Jared`/`JaredTests`. These LSP errors are stale and not real compile failures.

## Architecture Overview

Jared is a macOS iMessage bot. It polls the local Messages SQLite database (`~/Library/Messages/chat.db`) every ~5 seconds for new rows, constructs `Message` objects, and routes them through a plugin system.

**Data flow:**
```
DatabaseHandler (SQLite polling)
  → Router.route(message:)
    → MessageDelegate.didProcess() [webhooks notified of every message]
    → Route comparisons matched → route.call(message) [plugin handler invoked]
```

**Outgoing messages** are sent via AppleScript (`.scpt` files bundled in the app). Different scripts handle group chats vs. 1:1 conversations.

## Key Components

| File/Target | Role |
|---|---|
| `JaredFramework/` | Public API framework; shared with plugins. Defines `Message`, `Route`, `RoutingModule`, `MessageSender`, entities, etc. |
| `Jared/DatabaseHandler.swift` | Polls `chat.db`, constructs `Message` objects, feeds them to `Router` |
| `Jared/Router.swift` | Matches incoming messages against all registered `Route`s |
| `Jared/PluginManager.swift` | Loads `.bundle` plugin files from `~/Library/Application Support/Jared/Plugins/`, manages `RoutingModule` list |
| `Jared/CoreModule.swift` | Built-in commands: `/ping`, `/send`, `/schedule`, `/name`, `/whoami`, `/barf`, etc. |
| `Jared/InternalModule.swift` | `/help`, `/reload`, `/enable`, `/disable` commands |
| `Jared/WebHookManager.swift` | Implements both `MessageDelegate` (notify on all messages) and `RoutingModule` (webhook-defined routes) |
| `Jared/JaredWebServer.swift` | REST API web server |
| `JaredUI/` | SwiftUI/AppKit macOS app wrapper (thin — mostly wires up the core) |

## Plugin System

Plugins are `.bundle` files implementing `RoutingModule`. A plugin must:
1. Set `JaredFrameworkVersion = "J3.0.0"` in its `Info.plist` — version must match exactly or the plugin is silently rejected (`PluginManager.loadBundle`).
2. Have a `principalClass` that conforms to `RoutingModule`.
3. Be placed in `~/Library/Application Support/Jared/Plugins/`.

See `Documentation/SampleModule/` for a reference implementation.

## Route Comparisons

`Route` uses a `[Compare: [String]]` dictionary. Available comparison types (case-insensitive matching):
- `.startsWith` — message text starts with any of the strings
- `.contains` — message text contains any of the strings
- `.is` — message text exactly equals any of the strings
- `.containsURL` — message contains a URL that contains any of the strings
- `.isReaction` — message has a tapback/reaction (`message.action != nil`)

## Message Parameters

Commands parse parameters by splitting on commas: `message.getTextParameters()` returns `[String]?`. Example: `/send,3,1,Hello` → `["send", "3", "1", "Hello"]`. Use `parameters[safe: index]` (extension on Array) to avoid out-of-bounds.

## Configuration

Runtime config at `~/Library/Application Support/Jared/config.json`. Schema:
```json
{
  "routes": { "routename": { "disabled": true } },
  "webhooks": [{ "url": "https://...", "routes": [] }],
  "webServer": { "port": 3005 }
}
```
Route names in `config.routes` are lowercased keys matching `Route.name.lowercased()`.

## Entities & Recipients

- `Person` — 1:1 iMessage handle (email or phone number) or the local user (`isMe: true`)
- `Group` — group chat, handle contains `;+;` or `;-;`
- `AbstractRecipient` — use when handle type is unknown; `getSpecificEntity()` resolves to `Person` or `Group`
- `message.RespondTo()` — returns the correct reply recipient (sender for 1:1, group for group chats)

## Testing Patterns

Tests are in `JaredTests/`. Mocks live in `JaredTests/Mocks/`:
- `JaredMock` — stub `MessageSender`
- `MockPluginManager` — tracks route call counts via `callCounts[routeName]`
- `MockRouter` — captures routed messages
- `URLProtocolMock` — intercepts URLSession for webhook tests

Test helpers in `JaredTests/DatabaseTestHelper.swift` use `scaffold.db` (a real SQLite file checked in) for `DatabaseHandler` tests.

## macOS Permissions Required at Runtime

- **Full Disk Access** — needed to read `~/Library/Messages/chat.db`
- **Automation (Messages app)** — needed for AppleScript sending (macOS Catalina+)
- **Contacts** (optional) — for resolving contact names

The app checks these at launch and stores status in `UserDefaults` under keys in `JaredConstants`.

## GitHub Repository

**Repo**: `ericdahl-dev/Jared` (https://github.com/ericdahl-dev/Jared)
- Branch protection on `master` — all changes must go through PRs
- Use `gh pr create --repo ericdahl-dev/Jared` and `gh pr merge --repo ericdahl-dev/Jared`
- Release process: archive with `JaredUI` scheme → export with Developer ID (team `5HR8E5CWR7`) → notarize with `xcrun notarytool` (keychain profile: `notarytool`) → staple → zip with `ditto -c -k --sequesterRsrc --keepParent`

## Localization

Localizable strings are in `Jared/en.lproj/Localizable.strings` and `Jared/ja.lproj/Localizable.strings` (Japanese). Use `NSLocalizedString("key")` — no `comment:` parameter in this codebase.

## Agent skills

### Issue tracker

GitHub Issues on `ericdahl-dev/Jared` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at repo root when they exist. See `docs/agents/domain.md`.
