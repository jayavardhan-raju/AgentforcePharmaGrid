---
layout: default
title: Agentforce Grid Integration
parent: API Reference
nav_order: 2
---

# Agentforce Grid Integration

This project does not contain any Lightning Web Components. The user-facing surface is the **Agentforce Grid** standard component on the `Inventory_Position__c` record page, configured to use:

1. The `Inventory_Transfer_Ops` list view as its row source.
2. The `IST_Inventory_Recommendation` prompt template for the per-row recommendation column.
3. The `Execute_Inter_Store_Transfer` Flow as the per-row action behind the Transfer/Optimize button.

Each of these is documented below.

---

## List View: `Inventory_Transfer_Ops`

Defined in `objects/Inventory_Position__c/listViews/Inventory_Transfer_Ops.listView-meta.xml`.

| Property | Value |
|---|---|
| `fullName` | `Inventory_Transfer_Ops` |
| `label` | `Inventory Transfer Ops` |
| `filterScope` | `Everything` |

**Columns** (in order):

`NAME`, `OBJECT_ID`, `Store__c`, `Medication__c`, `Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Medication_DEA_Schedule__c`, `Medication_Cold_Chain__c`, `Status__c`, `Status_Color__c`, `Recommendation_Preview__c`, `Recommendation__c`, `CREATED_DATE`.

`Medication_DEA_Schedule__c` and `Medication_Cold_Chain__c` are cross-object formula fields on `Inventory_Position__c` (list views cannot render lookup-target fields directly), so the Schedule II / cold-chain attributes that drive demo scenarios 1, 2, 4, and 5 are visible in the grid. The grid is reachable from the `Inventory_Position__c` custom tab (Inventory Positions).

`Recommendation__c` is included for completeness, but the Grid surface that ops users interact with renders `Recommendation_Preview__c` because Long Text Area is not a supported Grid column type.

---

## Prompt Template: `IST_Inventory_Recommendation`

**Authored manually in Prompt Builder — not shipped as package metadata.** Salesforce's `GenAiPromptTemplate` type requires server-generated hash identifiers that cannot be hand-written, so the template was removed from `force-app/` in May 2026 and is now created in the target org by an admin following [Create the Prompt Template](../setup/create-prompt-template.html). `PostInstallScript.verifyPromptTemplate()` queries `AiPrompt` after install and logs `LoggingLevel.WARN` if the developer name is missing.

| Property | Value (after manual creation) |
|---|---|
| Type | `GenAiPromptTemplate` |
| `DeveloperName` | `IST_Inventory_Recommendation` |
| `MasterLabel` | `IST Inventory Recommendation` |
| `ActiveVersion` | `1` (after Activate is clicked in Prompt Builder) |
| Input | `$Input:Inventory_Position__c` (single record input) |

The active version takes a single input — `$Input:Inventory_Position__c` — and merges these record fields:

- `Id`, `Store__r.Name`, `Medication__r.Name`
- `Medication__r.DEA_Schedule__c`, `Medication__r.Cold_Chain_Required__c`
- `Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Status__c`

### Prompt rules

The system prompt encodes six rules verbatim. Paraphrased:

1. **Schedule II override** — output the literal sentence: *"Schedule II: Manual DEA Form 222 transfer required. No automated action available."*
2. **Critical and not Schedule II** — output: *"Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action."*
3. **Adequate but approaching reorder** (`Quantity__c < 2 × Safety_Stock__c`) — output: *"Stock adequate but approaching reorder threshold. Monitor closely."*
4. **Adequate and healthy** (`Quantity__c >= 2 × Safety_Stock__c`) — output: *"Stock levels healthy. No action required at this time."*
5. **Near-expiry prefix** — if `Expiry_Date__c` is within 30 days, prepend `"EXPIRY ALERT: "` to whichever of rules 1–4 applied.
6. **Output formatting** — never recommend specific transfer quantities (those come from `calculateTransferQty()` at execution time); keep total output under 150 characters; output only the recommendation sentence — no preamble, no JSON, no labels.

> The prompt template's "Critical" and "Adequate" labels are **the prompt's own taxonomy**, not values that exist on the record. The `Status__c` formula on `Inventory_Position__c` outputs `OUT_OF_STOCK`, `LOW`, `HEALTHY`, or `UNKNOWN`. The prompt is being asked to interpret these values against the prompt's own thresholds (e.g. "Critical" ≈ `OUT_OF_STOCK` per rule 2's `Quantity <= 0` clarifier). This is an LLM correctness risk — model outputs can drift from these rules — and is worth either tightening the prompt to use the actual `Status__c` enum values, or adding evals.

---

## Flow: `Execute_Inter_Store_Transfer`

Defined in `flows/Execute_Inter_Store_Transfer.flow-meta.xml`.

| Property | Value |
|---|---|
| `apiVersion` | `65.0` |
| `processType` | `AutoLaunchedFlow` |
| `status` | `Active` |
| `interviewLabel` | `Execute_Inter_Store_Transfer {!$Flow.CurrentDateTime}` |

### Variables

| Name | Type | Input | Output | Notes |
|---|---|---|---|---|
| `inventoryPositionId` | String | ✓ | — | Bound to `{Salesforce.Id}` from the Grid row |
| `confirm` | Boolean | ✓ | — | Input variable on the Flow definition, but **not** mapped on the action call (see note below) |
| `recommendedQty` | Number(2) | — | ✓ | Returned to caller (currently unused by the Grid) |
| `refreshView` | Boolean | — | ✓ | Set to `true` after the action call to trigger record-page refresh |
| `sourceStoreId` | String | — | ✓ | Reserved for future use; not currently surfaced |
| `sourceStoreName` | String | — | ✓ | Reserved for future use; not currently surfaced |
| `success` | Boolean | — | ✓ | Mirrors `ActionOutput.success` |
| `transferLogId` | String | — | ✓ | Mirrors `ActionOutput.transferLogId` |
| `uhText` | String | — | ✓ | Mirrors `ActionOutput.uhText` |

### Steps

1. **Start** → action call `Execute_Inter_Store_Transfer` (`actionType = apex`, `actionName = InterStoreTransferAction`), passing `inventoryPositionId`. `storeOutputAutomatically = true`.
2. **Action call** → assignment `refreshv1`, which sets `refreshView = true`.

> Note: the Flow does **not** pass `confirm` to the action. It only passes `inventoryPositionId`. As a result, the action receives a null `confirm`, and `InterStoreTransferAction.execute` falls back to `confirm = false` (the dry-run path). This means the current Grid wiring only ever calls the dry-run; executing requires the agent to call the action a second time with `confirm = true`. If you want the Grid button itself to execute on confirmation, you'll need to add a confirmation screen flow or pass `confirm` from the Grid action input mapping.

---

## Grid Configuration (Lightning App Builder)

The Agentforce Grid component must be added to the `Inventory_Position__c` record page (`Inventory_Position_Record_Page`) with the following configuration:

| Setting | Value |
|---|---|
| Source list view | `Inventory_Transfer_Ops` |
| Recommendation column → Prompt template | `IST_Inventory_Recommendation` |
| Recommendation column → Display field | `Recommendation_Preview__c` |
| Action button → Label | `Transfer/Optimize` |
| Action button → Type | Flow |
| Action button → Flow | `Execute_Inter_Store_Transfer` |
| Action button → Input mapping | `inventoryPositionId` ← `{Salesforce.Id}` |

The `{Salesforce.Id}` merge syntax is the per-row record ID. The Grid passes it to the Flow input variable on each click.
