# iOS 27 features (`POLARIS_IOS27`)

iOS 27 ships several on-device AI and platform capabilities this app is built
to use. Because they depend on beta SDK symbols that don't exist in the iOS 26
SDK, the code that calls them is compiled in only when the **`POLARIS_IOS27`**
flag is set. Everything else — the architecture, data collection, UI wiring,
and graceful fallbacks — is live on every build and exercised by CI on
Xcode 26.

## Turning it on

In `project.yml`, set:

```yaml
SWIFT_ACTIVE_COMPILATION_CONDITIONS: "POLARIS_IOS27"
```

then regenerate (`xcodegen generate`) and build with Xcode 27 on a device
running the iOS 27 developer beta. Leave it empty for CI / Xcode 26.

> The beta API call sites are marked `VERIFY` in code. Confirm each signature
> against the installed iOS 27 SDK before relying on it — the shapes below are
> written to match the announced flow, not copied from a shipping header.

## What's gated vs. always-on

| Feature | Always on (iOS 26 + CI) | `POLARIS_IOS27` only |
| --- | --- | --- |
| **On-device fine-tuning** (`PersonalizationAdapter`) | Collects + persists the correction training set, retrain trigger, de-dupe, bounded corpus | LoRA `train()` + adapter load, attaching the adapted model to sessions |
| **Multimodal receipts** (`FoundationModelsAIService.extractReceipt(image:)`, `ReceiptCaptureService`) | Protocol seam, image-first call site, OCR fallback when it returns `nil` | Passing the `CGImage` into guided generation |
| **Expanded context** (`classificationPrompt`) | Engine supplies up to 32 ranked few-shot examples | `if #available(iOS 27)` raises the prompt cap from 8 → 32 (no flag needed; runtime gate) |
| **Conversational Siri** (`SpendingCheckInIntent`) | Follow-up parameter prompt (`requestValueDialog`), snapshot-backed answer | `if #available(iOS 27)` pace-aware enrichment (no flag needed) |
| **Apple Cash split** (`SplitBillService`, `TransactionDetailView`) | Service seam; entry point hidden when unavailable | Wallet Split-Bill request flow |
| **Reorderable goals** (`SavingsGoal.sortIndex`, `GoalsView`) | Full drag-to-reorder via stable `List`/`.onMove` | — |

## Notes

- `if #available(iOS 27.0, *)` gates *runtime behavior that uses only existing
  symbols* (e.g. a larger prompt cap). It compiles under Xcode 26 and needs no
  flag.
- `#if POLARIS_IOS27` gates *code that references beta-only SDK symbols*
  (LoRA trainer, multimodal `Prompt.Image`, `PKApplePayLaterSplitRequest`).
  Without the flag those lines aren't compiled, so CI stays green.
- The personalization corpus is stored at
  `Application Support/Personalization/classifier-corrections.json` and never
  leaves the device.
