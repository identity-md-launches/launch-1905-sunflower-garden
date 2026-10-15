# Sunflower Garden design system

## Overview

Sunflower Garden is a static launch site and educational liquidity-range calculator for $SUN / IMD. Its visual idea is a precise protocol interface inhabited by sunflowers and bespectacled bees. The main tool shares the opening desktop grid with the introduction and remains on the first phone screen. No wallet, account, transaction or custody interface is present.

The source of truth is `site/index.html`, `site/assets/style.css`, `site/assets/app.js` and `site/assets/model.js`. `dist/` is an identical static export. The requested dark theme takes precedence over the creative brief’s contradictory cream background; the cream remains the text color. Artwork uses the specified golden yellow, leaf green and brown. Original SVG artwork supplies the logo, garden, wallet concept and six distinct meme compositions.

## Colors

Canonical values live in `:root` in `site/assets/style.css`.

| Token | Value | Role |
| --- | --- | --- |
| `--bg` | `#121610` | Page background |
| `--surface` | `#191f15` | Tool and alternating section backgrounds |
| `--surface-hover` | `#242c1e` | Hover, selected tabs and bee explanation |
| `--ink` | `#fffbe7` | Primary text |
| `--muted` | `#b5bdaa` | Descriptions and captions |
| `--subtle` | `#919f83` | Secondary illustration guidance |
| `--line` | `#38432d` | Structural borders and separators |
| `--accent` | `#ffd433` | Main action, slider, SUN allocation and sunflower petals |
| `--accent-hover` | `#ffe16a` | Main action hover |
| `--green` | `#89ba50` | Leaves, selected risk tier and swarm allocation |
| `--brown` | `#403511` | Text on yellow and sunflower face |
| `--focus` | `#fffbe7` | 2px focus outline, 5px offset |

Color never carries a state alone: selected controls also use `aria-pressed` or `aria-selected`, and risk states have explicit names and descriptions. The chart glow is a radial SVG gradient behind artwork, not behind interface text. Measured contrast checks are recorded in `artifacts/validation.md`; artwork is not represented as measured interface text.

## Typography

Three Google Fonts families are stored locally in `site/assets/fonts/`, with no runtime request to Google:

- Fredoka: display, section headings and brand; weight 500.
- Montserrat: body, labels and buttons; weights 400, 500 and 600.
- IBM Plex Mono: numbers, relative prices and full addresses; weights 400 and 500.

Font files include 400, 500 and 600; OFL notices are in `licenses/`. CSS uses `font-display: swap`. Display fallbacks are sans-serif; number fallbacks are monospace.

The six size tokens are `--text-xs` (13px), `--text-sm` (16px), `--text-md` (20px), `--text-lg` (28px), `--text-xl` (44px), and `--text-display` (72px). At 1150px, XL becomes 36px and display becomes 56px. At 760px, LG becomes 20px, XL 28px and display 44px. The probe measured six desktop sizes and five mobile sizes. Dense interface descriptions use 13px; the desktop introduction uses 16px. There are no extra sizes for individual sections.

Body line height is 1.65. Headings use 1.13, with the mobile hero at 1.08. Display tracking is −0.035em, section headings −0.025em, and smaller headings −0.015em. Body tracking is natural. Prose is capped at 66ch and wraps with `text-wrap: pretty`; headings use balanced wrapping. Numbers have tabular numerals. Addresses wrap with `overflow-wrap: anywhere`; no critical address is truncated.

## Layout

The shared `.shell` caps content at 1248px, using 48px outer margins on desktop. The opening layout uses 12 columns: 5 for the hero and 7 for the tool. Content sections use consistent two-column heading/description layouts, three-column tier and roadmap layouts, and a three-column meme wall.

Spacing tokens use 4, 8, 12, 16, 24, 32, 48, 64 and 96px. Desktop sections use 88px vertical padding, becoming 64px below 1150px and 48px below 760px. Related controls use 8–16px gaps; independent groups use 24–80px.

Breakpoints:

- Above 1600px: more opening vertical space, same capped content width.
- At 1150px: 32px margins, smaller headings, header CTA removed, footer and market data wrap.
- At 760px: 20px margins; stacked hero/tool, disclosure menu, one-column sections and risk tiers, two-column meme wall, full-width wrapped contract addresses. Garden scene reserves 220px so risk explanations fit without covering controls.
- At 390px: 16px margins, two-line brand, one-column meme wall and compact tool controls.

Home and 404 pages were checked at 320, 375, 390, 768, 1440 and 1920 CSS pixels. No horizontal overflow or broken images was observed. The final mobile screenshot and measured slider position are included in `artifacts/`. Browser-native zoom and physical devices remain unverified.

## Elevation & Depth

Surfaces are flat tonal layers with 1px structural borders. There are no box shadows or nested card systems. One subtle SVG glow suggests sunlight behind the main flower. The header is sticky with z-index 30. The bee explanation is a local overlay at z-index 5. The status toast uses z-index 70; the keyboard skip link uses 100. None is a modal dialog.

## Shapes

`--radius-sm` is 8px for actions. `--radius-lg` is 20px for the range tool and tier controls. The bee explanation and meme compositions use 12px. The bee help button is a compact capsule; the back-to-top control is round. Artwork shares rounded petals, circular faces, oval wings and rounded honey jars.

## Components

| Pattern | Source and behavior |
| --- | --- |
| `.button.primary` | Yellow main action; hover brightens, press scales to 0.96, keyboard focus uses the shared outline. |
| `.button.secondary`, `.copy-button`, `.text-link` | Secondary actions and address copying. Missing SUN address disables only its copy button. Copy success or failure is announced through a persistent polite status region. |
| `.site-header`, `#mobile-nav` | Sticky navigation. Mobile menu toggles `aria-expanded`, closes on Escape and selection, and clears when returning to desktop. It is a disclosure, not a modal. |
| `.plot`, `#range-width` | Native 5–80% range input, default 30%. Keyboard, pointer and chart dragging update one deterministic model. Values are illustrative, never presented as an actual market range or balance. |
| `#garden` | Widths 5–7 show seeds, 8–19 show sprouts, and 20–80 show growing flowers. Height, bee speed, honey fill and chart bounds derive from the same selected width. |
| `.tier` | Three preset buttons select narrow (10%), balanced (30%) or wide (65%). `aria-pressed`, border and explanatory text remain synchronized. |
| `.bee-popover` | Click to explain the selected risk tier; Close or Escape restores focus to the trigger. Mobile reserved space avoids collision with the slider. |
| `.buy-steps`, `.buy-panel` | Three tabs with roving tab index. Arrow keys, Home and End select steps; Next advances the guide. A Buy link is shown only when the feed supplies a valid URL. |
| `.address-row` | Full readable addresses with labeled copy actions. SUN stays `launching…` until a valid address arrives. |
| `.market-strip` | Absent values are hidden. Zero is valid data. Refresh errors keep received data with a stale-data label; Refresh retries. Updates every 30 seconds while visible. |
| `.meme`, `.share-actions` | Six SVG compositions with direct local PNG downloads; three distinct X intents and a canonical-link copy control. |

Motion uses CSS/SVG, not canvas or 3D: wing flaps, bee flight, plant scaling, an IntersectionObserver entrance, subtle magnetic primary action and number interpolation. Transitions name their properties. `prefers-reduced-motion` disables animations and smooth scrolling; the header’s Pause control disables decorative motion. There is no scroll-hijacking or initially invisible content.

## Do’s and Don’ts

Reuse `.shell`, `.section`, the six type tokens, semantic colors and existing actions when adding a page. Keep the main task early, put directions beside its controls, and retain readable full addresses. For a new static page, create its own folder under `site/`, use relative asset URLs adjusted for that folder, and export it with the copy script.

Do not present the illustrated chart as market history, honey as an account balance, or bees as an optimizer operating on funds. Do not add wallet SDKs, collection forms or trackers. Do not claim an audit, a partnership, realized governance, yield or a treasury fee. Future transaction features require a separately scoped implementation. The current site’s required transaction behavior is navigation to the feed’s external coin page.
