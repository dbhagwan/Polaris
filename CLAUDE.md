# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spendrift is an AI-first personal finance copilot for iOS 26+/iPadOS 26+ (Swift 6, SwiftUI, SwiftData, WidgetKit, Swift Charts, VisionKit) with a TypeScript backend scaffold for Plaid integration and AI orchestration. The hero feature is **Safe to Spend Today** — everything else feeds or explains that number.

## Build & Run

The Xcode project is generated, not checked in:

```bash
xcodegen generate        # requires: brew install xcodegen
open Spendrift.xcodeproj
```

Targets: `Spendrift` (app) and `SpendriftWidgets` (widget extension, shares `Core/Models`, `Core/Utilities`, and `SharedSnapshotStore.swift` via project.yml source entries). When adding a model or utility the widgets need, no project change is required; for other shared files, update the `SpendriftWidgets.sources` list in `project.yml`.

The app defaults to **mock mode** (`AppEnvironment(useMocks: true)` in `App/SpendriftApp.swift`) — `MockSyncService` seeds `PreviewContent/SampleData.swift` and everything runs without a backend.

Backend:

```bash
cd Backend && npm install && npm run dev   # needs .env (copy .env.example) + Postgres schema in src/db/schema.sql
npm run typecheck
```

Icons: `python3 scripts/generate_icons.py` (Pillow).

## Architecture — the part that matters

**All derived state flows through `Core/AI/AIPipeline.swift` (`recompute`).** It runs the full pipeline: pending/posted dedupe → transfer detection → recurring detection → receipt-to-transaction matching → `SpendingProfileEngine` → `ForecastEngine` (forecast + budget risk) → `SafeToSpendEngine` → AI narratives → net-worth snapshot → widget snapshot (`SharedSnapshotStore` in the App Group, then `WidgetCenter.reloadAllTimelines()`). Any mutation that affects money (category correction, budget edit, account hidden, receipt matched) must end with a `pipeline.recompute(in:)` call — views already do this via `AppEnvironment`.

**Structured AI only.** Model-backed inference goes through the `AIInferenceService` protocol and returns validated value types defined in `Core/Models/AIOutputs.swift` (`SpendingProfile`, `SpendForecast`, `BudgetRiskAssessment`, `SafeToSpendDecision`, `SpendingInsight`, `Recommendation`, `WidgetSnapshot`). Never render raw model text; insights/recommendations must carry `evidence` and `confidence`.

**On-device AI.** `FoundationModelsAIService` (Apple Foundation Models / Apple Intelligence, iOS 26) is the production `AIInferenceService` — classification, receipt extraction, and narratives all run on device via `@Generable` guided generation. Every method checks `SystemLanguageModel.default.availability` and falls back to `MockAIService` heuristics (ineligible devices, AI disabled, simulators/CI). Keep prompts terse — the on-device model has a small context window; `compactSummary` exists for that reason.

**Categorization is layered** (`Core/AI/CategorizationEngine.swift`): user correction memory → rules → provider hint → AI fallback. User corrections always win (`categorySource == .user`, confidence 1.0) and are learned via `learn(merchant:category:)`. Don't overwrite user-sourced categories anywhere.

**Safe-to-spend** (`Core/AI/SafeToSpendEngine.swift`) = deterministic base (remaining discretionary budget − upcoming recurring discretionary − unreserved essential, ÷ days left) × behavioral adjustment clamped to [0.7, 1.2], with every adjustment pushed into `adjustmentReasons` for the explanation drawer. Keep the clamp and the reasons — explainability is a product requirement.

**Dependency injection:** `App/AppEnvironment.swift` is the composition root, injected via SwiftUI `.environment()`. Previews use `AppEnvironment.mock()` + `ModelContainerFactory.preview()` (in-memory, seeded).

**Secrets:** Plaid access tokens and model API keys exist only in `Backend/`. The device stores only a session token / Apple user ID in the Keychain (`KeychainStore`). Don't add provider API calls to the iOS app.

**iCloud sync (three channels):** (1) SwiftData→CloudKit private database (`ModelContainerFactory` — falls back to local-only when iCloud is unavailable, e.g. simulators/CI); because of CloudKit rules, `@Model` classes must have **no `@Attribute(.unique)`** and **every stored property needs a default value** — keep this invariant when adding models. (2) iCloud Keychain (`KeychainStore` items are `kSecAttrSynchronizable`) carries credentials so a new device is pre-authenticated and the backend returns the same Plaid-linked institutions. (3) `NSUbiquitousKeyValueStore` syncs the categorization correction memory. Entitlements live in `project.yml`.

**Money convention:** `Transaction.amount` is positive for money out, negative for money in (Plaid convention). Spend totals must filter via `countsAsSpend` (excludes transfers, reimbursements, hidden, superseded pending, and excluded categories).

## Backend notes

`Backend/src/ai.ts` calls the Anthropic API (model `claude-opus-4-8`) with structured outputs (`output_config.format` + zod validation). `Backend/src/index.ts` contains an inline job runner explicitly marked TODO for replacement with a real queue. Plaid webhook → enqueue sync → `/transactions/sync` cursor-based upsert.

## Design system

**Dark-first glass** (Robinhood/Apple Stocks direction): the app targets iOS 26 and uses real Liquid Glass (`.glassEffect`) — it forces dark mode (`.preferredColorScheme(.dark)` in `SpendriftApp`) and every screen sits on `AppBackground` (black + aurora accent glows). `Card` renders `.glassEffect(.regular, in:)`; List screens use `.scrollContentBackground(.hidden)` + `.glassListRow()`. One accent color (mint, `Assets.xcassets/AccentColor`). Liquid Glass lives only in `Card`/`glassListRow` in `Core/DesignSystem/Theme.swift`. Building requires Xcode 26 (CI selects it explicitly).

Shared components in `Core/DesignSystem/Theme.swift`: `Card`, `AmountText` (respects privacy mode — always use it for currency), `ProgressRing`, `ConfidenceBadge`, `SkeletonBlock`, `EmptyStateView`. Widget financial values must be `privacySensitive()`.
