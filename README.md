# Sunflower Garden ($SUN)

Static launch website, interactive educational liquidity-range calculator, and a fixed-supply ERC-20 for the specified Robinhood Chain launch. The ready-to-serve website is in `site/` and its production export is in `dist/`.

## Preview and rebuild

The website is plain HTML, CSS and ES-module JavaScript. It has no runtime dependencies and requires no transpilation or bundling. All fonts, logo artwork and six PNG downloads are local.

With Node.js 22 or newer:

```sh
node scripts/build.mjs
node scripts/preview.mjs
```

Open `http://127.0.0.1:4173/preview/`. Stop the preview with Ctrl+C. The build command validates basic metadata, copies the token source into the website for its source-download link, and copies `site/` to `dist/`. Rebuild after changing source. Serve `dist/` as the static hosting root; `/preview/` is only a local subpath used to verify relative assets. Hosting and deployment are performed after submission, not by these scripts.

The shared stylesheet and font files also style `site/404.html`. A host must map missing routes to `404.html`; an arbitrary static server does not infer this automatically. Extra pages should be their own exported folders. All current assets use relative URLs; the deployment feed intentionally uses the origin-root `/simd-coin.json` required by the assignment.

## Install checks

Only development checks need packages. `package.json` and `package-lock.json` pin TypeScript, Playwright and axe-core:

```sh
npm ci
npm run typecheck
npm test
npx playwright install chromium
npm run test:browser
npm run check:budget
```

Do not submit `node_modules`, npm caches, browser binaries or generated test scratch output. During this task, check tools and browser downloads were installed into temporary storage outside the repository; no repository dependency/cache tree was created. `scripts/browser-check.mjs` also accepts `--playwright=<absolute module path>` and `--axe=<absolute module path>` for externally installed tools. It runs a bounded local preview and closes the server and browser when finished. It saves compact evidence in `artifacts/`.

`npm run typecheck` runs `tsc --noEmit` over the actual JavaScript through strict `checkJs` and JSDoc. The production copy script has no package dependency. The PNG downloads are complete committed assets, with editable SVG versions beside them; no image-generation service is needed to serve or rebuild the website.

## Launch data

`site/assets/app.js` fetches `/simd-coin.json` immediately, every 30 seconds while visible, and when the page regains visibility. Requests time out after eight seconds and can be retried with Refresh. The response is treated as data, not markup.

- `token`: a full nonzero address enables address copying. Until then the site shows `launching…`.
- `coinUrl` / `chartUrl`: valid HTTPS or same-origin URLs enable the Buy and Chart links. They are never guessed.
- `logo`: a valid URL replaces the default brand images; an image failure restores the local default.
- `market.priceUsd`, `market.marketCap`, `market.volume24h`: only finite nonnegative numbers are shown; missing values are hidden. Numbers animate between actual received values. The provided market fields are displayed as USD.

`site/simd-coin.json` is exactly `{}`: an explicitly empty static-host fallback, not sample market data. The publisher must serve its real same-origin feed at `/simd-coin.json` when available. The local preview responds with the same empty object. Browser test fixtures are confined to tests and are never included in the website.

No supplied logo files were present in the task workspace. A new original sunflower-and-bee SVG system and corresponding `logos/logo-1.png` were created. The default is copied into the site and the feed’s logo remains preferred when supplied. The static social image uses that default PNG; social crawlers generally do not execute JavaScript.

## Scope and resolved brief conflicts

The complete live brief was read at `https://www.si-md.xyz/api/chat?op=site-brief&label=sunflowergardensun`. The site keeps its ordered seven core sections, sunflower plot, bee explanations, wallet-garden concept, tokenomics, interactive buying guide, transparency section, roadmap, six meme compositions and share controls. The explicit dark theme is used with the creative palette and Fredoka/Montserrat typography.

The binding mechanics and no-wallet/no-data-collection rules take precedence over incompatible creative copy:

- Only the immutable **0.5% creator tax** exists. The creative brief’s 0.1% treasury fee is not implemented or advertised as active.
- The calculator and illustrative chart work now. Five-wallet monitoring, automated routing of single-sided deposits, oracles, timelock phase progression, utility access and governance are described as planned, not simulated as live products.
- No wallet connects here; no addresses or other visitor data are collected. Swaps, signatures and any transaction risk acknowledgment belong to the external DEX interface.
- Honey and plants visualize the selected range only. There are no invented balances, APYs, price histories, partnerships or audit claims. Meme captions are labeled community art, not forecasts.
- The range demonstration’s 5–80% bounds, 30% default, 10/30/65% tier presets, and 1× reference price are interface constants selected for teaching. They are not pool parameters or recommended trades. No fee or real opening price was chosen by the site.
- The requested complete `launch.json` is delivered under the mandatory build requirements; its authoritative initialPrice and economics override the contradictory background reference. Chain id is not a manifest field.

## Token and Foundry

`src/SUNToken.sol` has no imports. `foundry.toml` pins solc 0.8.26, Cancun, optimizer enabled (200 runs) and `bytecode_hash = "none"`. There is no FFI, filesystem permission, proxy, owner, mint-after-launch, burn, pause, blacklist, upgrade or admin function.

| Parameter | Fixed value |
| --- | --- |
| Name / symbol | Sunflower Garden / SUN |
| Supply / decimals | 1,000,000,000 / 18; `1e27` minor units |
| Constructor | No arguments; entire supply minted to `msg.sender` |
| Creator tax | 50 basis points; `floor(amount / 200)` |
| PoolManager | `0x8366a39cc670b4001a1121b8f6a443a643e40951` |
| Creator recipient | `0xEeaF04a41aC45A605E30dc6a41A44E6F75Ddf8b6` |
| Pair | IMD, `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Pool fee / tick spacing | 12500 (1.25%) / 60 |
| Factory allocation | 90% pool; 10% external swarm distributor |
| Opening market cap | 2500 IMD, as specified in the manifest |

Transfers **from** PoolManager debit the full amount, credit the creator’s tax directly, then credit the recipient with the remainder. This also taxes liquidity withdrawals and any other PoolManager outflow. Transfers **to** PoolManager take precedence and are untaxed, including a self-transfer. Ordinary wallet transfers, swarm distribution and swarm claims are untaxed. `transferFrom` consumes the gross allowance; infinite allowance remains infinite. Integer rounding keeps amounts below 200 minor units untaxed. No recipient call or external protocol call is made by the token.

The external launch factory performs distribution. The token does not reserve or transfer the swarm allocation. The manifest’s dead-address `remainderTo` is the exact requested address, not a guessed recipient; with the specified 90% pool and 10% swarm allocation no allocation remains. Any liquidity-rounding residual is handled by the launch factory, not by this token. `pool.initialPrice` is provenance; deployment derives actual currency ordering and opening price from the supplied economics.

Run:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xafedbd0c51c871146ac46750bcde0fa523713d34be6fab383f0b0d2bb53bc97f forge test -vv
```

Three suites run offline with no RPC and no environment variables. `test/SUNTokenSmoke.t.sol` holds one short scenario per numbered check in the launch brief (supply and decimals, deployer holds everything and the factory splits 10% / 90%, a taxed buy out of the PoolManager, an untaxed sell into it, a free wallet transfer, a balanced pool round trip, immutable rate and recipient, no owner or admin surface) plus the revert paths for insufficient balance, missing allowance and a zero receiver. `test/SUNToken.t.sol` adds events, rounding, allowance edge cases and two fuzz conservation checks. `test/UniswapV4.t.sol` runs the real PoolManager in both currency orderings.

Every Solidity import resolves to a delivered file. `lib/v4-core/` contains only the upstream PoolManager import graph needed for offline tests, pinned to commit `46c6834698c48bc4a463a86d8420f4eb1d7f3b75`. Its original licensing is retained. `lib/solmate/` contains its test-only Owned dependency. These contracts are **not** production launch contracts; the manifest lists only SUNToken and an empty application-contract array. There are no submodules. Foundry outputs and cache live under `test/scratch/`, which is excluded from delivery by the assignment.

The integration suite builds the real upstream PoolManager at the specified address and exercises single-sided seeding, a buy, a sell and liquidity withdrawal in **both currency orderings**. A simple test-only IMD implementation supplies test balances. This tests v4 accounting, not the live chain or every external router. Its settlement approach follows [Uniswap’s PoolManager source](https://github.com/Uniswap/v4-core/blob/46c6834698c48bc4a463a86d8420f4eb1d7f3b75/src/PoolManager.sol) and [v4 flash accounting guidance](https://developers.uniswap.org/docs/protocols/v4/guides/flash-accounting).

## Validation

Actual results are in `artifacts/validation.md` and `artifacts/browser-validation.json`. Screenshots are `artifacts/mobile.jpg` and `artifacts/desktop.jpg`. The design system is documented in `DESIGN.md`.

- Production static export and strict JavaScript typecheck passed.
- Six JavaScript model/security-boundary tests passed.
- Twenty-seven Foundry tests passed with the requested seed on solc 0.8.26 (`forge build`, `forge test`, `forge fmt --check`), including two 1,000-case fuzz tests and 40-transfer stateful conservation sequences per fuzz case, and the twelve smoke tests in `test/SUNTokenSmoke.t.sol`.
- Home and 404 pages passed overflow/image checks at 320, 375, 390, 768, 1440 and 1920px. Chromium interaction tests passed for the range slider, chart drag, tooltips, menu, buying guide, copying, PNG downloads, sharing, and live-data success/missing/malformed/retry/refresh behavior.
- Four axe-core page/width scans reported zero WCAG A/AA violations. This is not a claim of full accessibility conformance.
- The pinned taste@1 design probe passed all 16 checks. All six Better Interface domains were reviewed.

WebKit could not launch in the available environment, so Safari and physical-device behavior remain unverified. No manual screen-reader session, native browser zoom, live-chain fork, external wallet transaction or deployed data feed was tested. The protected input tests reference verifier-owned floor files not supplied to this project; they were read, not misrepresented as executed. No publishing, signing or deployment was performed.

The deliverable budget is checked with `node scripts/budget.mjs`. It counts raw deliverable bytes, rejects caches/dependency directories and archives, and enforces a conservative 7 MiB payload ceiling beneath the 8 MiB Git-bundle limit. No ignore file was added or changed. Git metadata is intentionally untouched, so an actual Git bundle was not created or inspected.

## Attribution

Original website and SUNToken implementation: this submission. Local fonts retain their SIL Open Font License notices. Design review applies the pinned Better Interface guide by Jakub Krehel (MIT), with Paul Bakaus’s Impeccable documentation guidance (Apache-2.0); their combined license is retained in `licenses/Better-Interface-LICENSE.txt`. Testing guidance by Austin Griffith is acknowledged in `licenses/eth-testing-LICENSE.txt`. Vendored Solidity dependencies retain their upstream source headers, licenses and provenance notes.
