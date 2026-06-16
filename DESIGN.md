# JaredUI Visual System

This document is the source of truth for the visual language used in JaredUI. It
captures the tokens that the current AppKit implementation in `JaredUI/` already
follows so that future contributions — including a SwiftUI rewrite — stay
visually consistent with the shipping app.

When in doubt, treat the values in this document as the design system. If a new
screen needs a token that isn't listed here, add it here first, then implement.

The reference implementation lives in `JaredUI/ViewController.swift`. Most
tokens below cite the exact lines they originate from.

## Materials

| Surface | Material | Notes |
| --- | --- | --- |
| Window header | `NSVisualEffectView` · `.sidebar` · `.behindWindow` · `.active` | 88pt tall, sits above the scrollable content. `ViewController.swift:94-127` |
| Body | Default window background | Scroll view uses `drawsBackground = false` so the window's background shows through. `ViewController.swift:153` |
| Separators | `NSColor.separatorColor`, 1pt | Between sections inside the scroll content. `ViewController.swift:268-275` |

A SwiftUI port should reach for `.regularMaterial` on the header equivalent and
keep the body transparent over the window background.

## Color

### Semantic state colors

State colors carry meaning. Do not use them decoratively.

| State | Color | Used for |
| --- | --- | --- |
| Running / authorized / OK | `systemGreen` | Healthy services, granted permissions, the "Running" subtitle in the header. `ViewController.swift:308-309`, `:610` |
| Warning / not set / partial | `systemOrange` | Permissions not yet requested, the "Disk access required" header state, tunnels still starting. `ViewController.swift:298-299`, `:612` |
| Error / denied / restricted | `systemRed` | Denied permissions, the "Disabled" header subtitle, hard failures. `ViewController.swift:303-304`, `:613` |
| Off / inactive / muted | `tertiaryLabelColor` | The "off but not broken" state of a row's status label. `ViewController.swift:611` |
| Primary action | `controlAccentColor` | Header CTA when enabling Jared. `ViewController.swift:306` |

These map to the `RowState` enum in `ViewController.swift:534`:

```
enum RowState { case on, off, warning, error }
```

Any new status surface must map to one of these states. Add to the enum if
nothing fits — don't invent ad-hoc colors at the call site.

### Identity colors (row icons)

Each row has a stable identity color used only for its rounded icon container.
These are decorative — never use them to communicate status.

| Row | Symbol | Identity color |
| --- | --- | --- |
| Jared | `bubble.left.fill` | `systemGreen` |
| Full disk access | `internaldrive.fill` | `systemBlue` |
| REST API | `network` | `systemIndigo` |
| LLM | `brain` | `systemTeal` |
| Webhooks | `bolt.horizontal.fill` | `systemPink` |
| Contacts | `person.fill` | `systemOrange` |
| Messages automation | `envelope.fill` | `systemPurple` |

Source: `ViewController.swift:160-166`. Icons are SF Symbols; new rows must use
SF Symbols and pick an identity color that isn't already in this table.

### Text colors

| Role | Color |
| --- | --- |
| Primary text (title, app name) | `labelColor` |
| Secondary text (subtitle, status, body) | `secondaryLabelColor` |
| Disabled / muted | `tertiaryLabelColor` |
| Section headers | `tertiaryLabelColor` (uppercased) |

## Typography

All text uses the system font via `NSFont.systemFont(ofSize:weight:)`.

| Token | Size | Weight | Example |
| --- | --- | --- | --- |
| App title | 18 | `.semibold` | "Jared" in header. `ViewController.swift:111` |
| Section header | 10 | `.semibold`, uppercased, `tertiaryLabelColor` | "STATUS", "SERVICES". `ViewController.swift:256` |
| Row title | 13 | `.medium` | "REST API", "LLM". `ViewController.swift:563` |
| Row status / header subtitle / tool button | 12 | `.regular` (or `.medium` for the header CTA) | "Running", "Authorized". `ViewController.swift:114`, `:119`, `:280`, `:568` |
| Row action button | 11 | `.regular` | "Enable", "Manage". `ViewController.swift:574` |

Sheet/secondary screens (e.g. `LLMSettingsViewController`) reuse the 12pt
regular and 11pt button conventions. A new screen should pick from this scale —
don't introduce a new size.

## Spacing & layout

A single horizontal margin token applies to the whole sidebar surface.

| Token | Value | Where it applies |
| --- | --- | --- |
| Side margin | **20pt** | Header content, section headers, status rows, tools row. `ViewController.swift:129`, `:232`, `:262`, `:586` |
| Action button trailing inset | 16pt | Row trailing edge to action button. `ViewController.swift:602` |
| Icon → title gap | 12pt | Between row icon container and title label. `ViewController.swift:134`, `:596` |
| Title ↔ subtitle gap | 3pt (rows), 3pt (header) | `ViewController.swift:138`, `:600` |
| Tool button row spacing | 8pt | Between buttons in the Tools row. `ViewController.swift:234-237` |
| Section header height | 30pt | `ViewController.swift:261` |
| Status row height | **56pt** | All `StatusRowView` rows and the Tools row. `ViewController.swift:231`, `:584` |
| Header height | 88pt | Visual effect header. `ViewController.swift:127` |

Vertical rhythm between rows is provided implicitly by each row owning a 56pt
frame — the surrounding `NSStackView` uses `spacing = 0`
(`ViewController.swift:194`). Do not add stack spacing; if a row needs more
breathing room, increase its own height.

## Iconography

Rows use a tinted rounded container with an SF Symbol centered inside it.

| Element | Value |
| --- | --- |
| Container size | 32 × 32pt |
| Container corner radius | 8pt |
| Container fill | identity color at **12% alpha** (`identityColor.withAlphaComponent(0.12)`) |
| Symbol size | 16 × 16pt |
| Symbol tint | identity color (full alpha) |

Source: `ViewController.swift:551-553`, `:587-594`.

The app icon in the header is a separate case: 52 × 52pt with a **14pt corner
radius** (`ViewController.swift:106`, `:131-132`).

## Components

### `StatusRowView`

Defined in `ViewController.swift:536`. The canonical row primitive:

```
icon container · title (13 medium) / status (12 regular, state-colored) · [optional rounded action button]
```

Construction: `StatusRowView(icon:iconColor:title:)` — the icon and identity
color are set once; mutation happens through `update(statusText:state:buttonTitle:)`.

When porting to SwiftUI: this is one row component with three slots
(leading icon, two-line text, trailing button). Don't split it into seven
bespoke views.

### Section header

`sectionHeader(_:)` in `ViewController.swift:252`. Just an uppercased 10pt
semibold label on a 30pt tall row, indented 20pt from the leading edge.

### Tool button

`toolButton(_:icon:action:)` in `ViewController.swift:277`. Rounded bezel, 12pt
font, SF Symbol leading. Used for the "Tools" row at the bottom of the sidebar.

## Authoring rules

1. **Pick state colors from the `RowState` table.** If your status doesn't map
   to on/off/warning/error, extend `RowState` and update this document.
2. **Don't introduce new font sizes.** Use the 18/13/12/11/10 scale.
3. **Don't introduce new identity colors without updating the table above.**
   Each row needs a unique identity color.
4. **Reuse `StatusRowView` for any "status with optional action" surface.**
   Don't reimplement the icon+title+status+button layout per screen.
5. **Side margins are 20pt.** Any inset that isn't 20pt should be deliberate
   and have a reason that fits in a code comment.
6. **SF Symbols only** for inline iconography. App icon is the only raster
   image.
