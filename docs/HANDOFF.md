# Polaris — Session Handoff

> Read this first in a new session to get up to speed. It captures project
> state, what's been built, what's parked, and the key constraints. Last
> updated: 2026-06-15.

## What Polaris is

An AI-first personal-finance copilot for iOS 26+/iPadOS 26+ (Swift 6, SwiftUI,
SwiftData→CloudKit, WidgetKit, Swift Charts, VisionKit) with a TypeScript
backend scaffold for Plaid + AI orchestration. The hero feature is **Safe to
Spend Today** — everything feeds or explains that number. All model inference
runs **on-device** via Apple Foundation Models, falling back to deterministic
heuristics (`MockAIService`) where unavailable. See `CLAUDE.md` for the full
architecture; the load-bearing rule is that all derived state flows through
`Core/AI/AIPipeline.swift` `recompute(in:)`.

> Note: the repo/product was renamed **Spendrift → Polaris**. The GitHub repo is
> now `dbhagwan/Polaris` (git remote still resolves via a redirect from the old
> `spendrift` name). The on-disk directory is `/home/user/Spendrift` but the
> app target/dirs are all `Polaris`.

## Branching & how this session worked

- Active dev branch: **`claude/repo-initialization-oydett`**. It was originally a
  stale init branch (pre-rename); this session fast-forwarded it to `main`
  (which had all the real work) and built on top. It now contains the full app +
  the iOS 27 work + Xcode Cloud scaffolding.
- The user develops entirely from a **cloud Linux Claude Code session** (their
  Mac "is old and dies often"). There is **no local Swift/Xcode** here — builds
  happen on CI (GitHub Actions, macOS, Xcode 26) or, going forward, Xcode Cloud.
- `git push` works (notes a "repository moved" redirect, succeeds anyway).
  Triggering GitHub Actions `workflow_dispatch` via the GitHub MCP currently
  **500s** because of the rename redirect on POST + the MCP being scoped to the
  old `spendrift` name. The user can trigger workflows from the GitHub UI.

## CI / build status

- **`.github/workflows/ci.yml`** — Backend typecheck (ubuntu) + iOS
  build-for-testing & UI screenshot tests (macos-15, Xcode 26). Runs on push to
  `main`, PRs, and manual dispatch. Does **not** auto-run on feature-branch
  pushes.
- **TestFlight**: `testflight.yml` (full entitlements) and `testflight-lite.yml`
  (strips App Group/iCloud/push for frictionless signing). The **lite build is
  VALID on TestFlight**. Full build path exists but the lite one is what's
  confirmed live.
- Repo secrets already configured: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_B64`,
  `APPLE_TEAM_ID` (team `YZ8Q9AQN73`). Bundle IDs are under
  `com.dbhagwan.polaris(.widgets/.watchkitapp/.uitests)`; App Group
  `group.com.dbhagwan.polaris`; iCloud `iCloud.com.dbhagwan.polaris`.

## iOS 27 features added this session (answer to "what did you add")

All gated so CI/Xcode 26 stay green: **beta-only SDK symbols** are compiled only
when the **`POLARIS_IOS27`** flag is set; **runtime-only** behavior changes use
`if #available(iOS 27.0, *)` and need no flag. Beta call sites are marked
`VERIFY` in code — they're best-guess API shapes, **not yet confirmed against the
real SDK**. Full detail in **`docs/iOS27.md`**.

**Tier 1 — on-device AI**
- **On-device fine-tuning** — `Core/AI/PersonalizationAdapter.swift` (new). An
  actor that collects/persists the user's category corrections as a de-duped,
  bounded LoRA training set with a retrain trigger. The corpus is gathered on
  *every* build; the actual LoRA `train()`, adapter load, and attaching the
  adapted model to `LanguageModelSession` are flag-gated. Wired through
  `AppEnvironment` and `AIPipeline.applyCorrection`.
- **Multimodal receipts** — `extractReceipt(image: CGImage)` added to the
  `AIInferenceService` protocol with a default-`nil` (Mock/iOS 26 fall back to
  OCR); flag-gated image extraction in `FoundationModelsAIService`;
  `ReceiptCaptureService.process` now tries the image path first, then OCR.
- **Expanded context window** — classification prompt feeds up to 32 few-shot
  examples on iOS 27 (8 on iOS 26); `CategorizationEngine.relevantExamples` now
  supplies the larger ranked slate.
- **Tool calling / @Generable** — already present (`CategoryHistoryTool`);
  unchanged this session.

**Tier 2 — platform**
- **Conversational Siri (App Intents 2.0)** — `App/PolarisAppIntents.swift`:
  `SpendingCheckInIntent` with a real follow-up prompt ("today or this week?")
  via stable `requestValueDialog`, plus iOS 27 pace-aware enrichment. Registered
  in `PolarisShortcuts`. Existing intents untouched.
- **Apple Cash bill split** — `Core/Services/SplitBillService.swift` (new) seam;
  entry point added to `TransactionDetailView` that shows only where the system
  can present it. (Distinct from the existing in-app category `SplitTransaction`.)

**Tier 3 — SwiftUI**
- **Reorderable goals** — `SavingsGoal.sortIndex` + drag-to-reorder via
  `List`/`.onMove` in `GoalsView` (stable API, works on iOS 26, fully CI-safe).

Commits: `9cef683` (features), `1d11633` (Xcode Cloud path).

## How to actually compile the iOS 27 paths (Xcode Cloud)

GitHub runners lag on Xcode betas, so they can't target the iOS 27 SDK. Xcode
Cloud gets Apple's beta toolchains within days. This session added the repo side:

- **`ci_scripts/ci_post_clone.sh`** — installs XcodeGen, generates the project
  (the `.xcodeproj` isn't checked in), and flips on `POLARIS_IOS27` when the
  build env sets it.
- **`.github/workflows/xcode-cloud-versions.yml`** — one-click read-only ASC API
  check listing the Xcode/macOS toolchains Xcode Cloud offers (confirms an Xcode
  27 beta exists before wiring the build; no Mac needed).

**Pending user action** (UI steps Claude can't do from here): run the version
check, then in App Store Connect → Xcode Cloud create a workflow on the `Polaris`
scheme, pick the Xcode 27 beta toolchain, action = Build, env var
`POLARIS_IOS27 = 1`. Do a baseline (flag off) run first to confirm the stable app
compiles on the iOS 27 SDK, then a flagged run — the flagged build's job is to
surface which `VERIFY` API signatures are wrong so they can be fixed iteratively.
To enable the flag locally instead: set
`SWIFT_ACTIVE_COMPILATION_CONDITIONS: "POLARIS_IOS27"` in `project.yml`.

## Parked / pending threads (not done)

1. **Verify & fix the iOS 27 `VERIFY` symbols** against the real SDK once an
   Xcode 27 build runs (LoRA trainer API, `Prompt.Image`,
   `PKApplePayLaterSplitRequest`, session `adapter:`/`model:` inits).
2. **Plaid production** — user wants **real-bank (production)** access, not
   sandbox. The iOS app currently defaults to **mock mode**
   (`AppEnvironment(useMocks: true)` in `App/PolarisApp.swift`); `BackendAPI`
   baseURL is `http://localhost:3000`. Connecting real banks needs the backend
   deployed and the app pointed at it + mock mode off.
3. **Backend hosting on Render free tier** — user will set up Render; needs the
   `Backend/` service deployed (Postgres schema in `src/db/schema.sql`, env from
   `.env.example`, Anthropic key + Plaid prod credentials server-side only).
4. **Full TestFlight build** (App Group/iCloud) — the lite build is VALID; the
   full-entitlements path needs the App ID's App Group/iCloud associations
   confirmed on the developer website.
5. **Monochrome + Liquid Glass redesign** (PARKED by user: "keep the original UI
   for now"). A complete cool monochrome white/black + Liquid Glass, dense design
   language was explored across all 11 screens and delivered as **HTML→PNG
   mockups only** (in `/tmp/mocks`, NOT in the repo, and the container is
   ephemeral so they're gone). Design DNA if revived: bg `#08080b`, white type,
   luminance-scaled categories, `.g` glass class (translucent + edge highlight +
   diagonal sheen + backdrop blur over ambient bloom), Space Grotesk numbers,
   Manrope UI. The user rejected: candy/emoji styles, a pink theme, and overly
   sparse layouts; liked notbor.ing's polish. This was never built in SwiftUI.

## Debt Payoff Planner (added)

A full debt-payoff feature, built to mirror the Goals→Safe-to-Spend pattern:
- `Core/AI/DebtPayoffEngine.swift` — pure, deterministic avalanche/snowball
  simulator (month-by-month interest accrual, minimum payments, snowball roll of
  freed minimums, extra-payment targeting). Returns debt-free date, total
  interest, payoff order, and interest/months saved vs. minimums.
- `Account` gained `apr` + `minimumPayment` (optional, CloudKit-safe);
  `UserProfile` gained `debtStrategy` + `debtMonthlyExtra`.
- The extra monthly payment reserves from safe-to-spend exactly like goals:
  `SafeToSpendDecision.debtDailyReservation`, threaded through
  `SafeToSpendEngine.decide` and computed in `AIPipeline.recompute`, surfaced in
  the explanation drawer (`HomeCards.swift`).
- `Features/Debt/DebtView.swift` (strategy picker, extra-payment slider, payoff
  order, per-liability APR/min editor) + a Home "Debt Payoff" card. Sample data
  now seeds three liabilities so avalanche vs. snowball differ.
- **First unit test target**: `PolarisTests` (`bundle.unit-test` in
  `project.yml`, added to the scheme) with `DebtPayoffEngineTests`, plus a
  dedicated `unit-tests` CI job in `ci.yml` that runs only those tests — a fast,
  reliable signal independent of the flaky UI screenshot suite.

## Hard constraints (keep these)

- **Secrets**: Plaid access tokens + model API keys live **only in `Backend/`**,
  never committed, never on device. The device Keychain holds only a session
  token / Apple user ID. No provider API calls from the iOS app.
- **Structured AI only**: inference returns validated value types
  (`Core/Models/AIOutputs.swift`); never render raw model text; insights/recs
  carry `evidence` + `confidence`.
- **CloudKit invariants**: `@Model` classes need **no `@Attribute(.unique)`** and
  **every stored property needs a default value**.
- **Money convention**: `Transaction.amount` positive = money out, negative =
  money in (Plaid). Spend totals filter via `countsAsSpend`.
- **Safe-to-spend explainability**: keep the [0.7, 1.2] behavioral clamp and push
  every adjustment into `adjustmentReasons`. Goals/rollover must surface in the
  explanation drawer.
- **Don't overwrite user-sourced categories** anywhere
  (`categorySource == .user`, confidence 1.0).
- **Commits**: author `Claude <noreply@anthropic.com>`; end commit messages with
  the session URL. Never put the model identifier (`claude-*`) in commits, code,
  PR text, or any pushed artifact.
- The user pasted a Plaid `.p8` ASC key in chat in an earlier session — they were
  advised to revoke + regenerate after testing.

## Key files map

- Composition root: `Polaris/App/AppEnvironment.swift`
- Pipeline: `Polaris/Core/AI/AIPipeline.swift`
- AI boundary: `Polaris/Core/AI/AIInferenceService.swift` (protocol + Mock)
- On-device AI: `Polaris/Core/AI/FoundationModelsAIService.swift`
- Personalization (new): `Polaris/Core/AI/PersonalizationAdapter.swift`
- Categorization: `Polaris/Core/AI/CategorizationEngine.swift`
- Receipts: `Polaris/Core/Services/ReceiptCaptureService.swift`
- Split bill (new): `Polaris/Core/Services/SplitBillService.swift`
- Intents: `Polaris/App/PolarisAppIntents.swift`
- Goals: `Polaris/Core/Models/Goals.swift`, `Polaris/Features/Goals/GoalsView.swift`
- Project gen: `project.yml` (XcodeGen) — `.xcodeproj` is NOT checked in
- iOS 27 docs: `docs/iOS27.md`; Xcode Cloud hook: `ci_scripts/ci_post_clone.sh`
