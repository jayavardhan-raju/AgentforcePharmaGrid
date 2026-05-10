# AgentforcePharmaGrid

**Agentforce Grid–driven inter-store inventory transfers for retail pharmacies — with built-in DEA Schedule II compliance, cold-chain enforcement, and full audit trail.**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Salesforce-00A1E0.svg)](https://www.salesforce.com)
[![API](https://img.shields.io/badge/API-v65.0-1798c1.svg)](https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/)
[![Agentforce](https://img.shields.io/badge/Agentforce-Grid-9B59B6.svg)](https://www.salesforce.com/agentforce/)

---

## Overview

AgentforcePharmaGrid is a Salesforce-native solution that lets a pharmacy ops team find low-stock medications across stores, get an Agentforce-generated recommendation per row, and execute an inter-store transfer with one click — all from an Agentforce Grid component.

The core logic lives in three Apex classes (`InterStoreTransferService`, `InterStoreTransferAction`, `InventoryPositionSelector`) plus a Flow (`Execute_Inter_Store_Transfer`) and a Prompt Template (`IST_Inventory_Recommendation`). There is no LWC, no middleware, and no external service. The Grid's per-row "Transfer/Optimize" button invokes the Flow directly, the Flow calls the Apex invocable action, and the action returns a structured `uhText` that surfaces back into the Grid conversation.

What makes this project different from a generic transfer utility:

- **Hard compliance gate** for DEA Schedule II — no source search, no recommendation, no execution. A blocked `Transfer_Log__c` record is still written for the DEA audit trail.
- **Cold-chain matching** — if the medication requires cold chain, only stores with `Cold_Chain_Capable__c = true` are eligible sources.
- **Near-expiry exclusion** — source stock expiring within 30 days is filtered out so we don't move soon-to-be-wasted inventory.
- **Two-call agent contract** — `confirm = false` writes a recommendation; `confirm = true` executes atomically with savepoint rollback. The agent surfaces the dry-run text and asks the user to confirm.
- **Grid-friendly preview field** — the full recommendation is in `Recommendation__c` (Long Text Area), and a 255-char `Recommendation_Preview__c` is what the Agentforce Grid column actually renders, since Long Text Area is not a supported Grid column type.

### Key Capabilities

- **Schedule II hard-stop** — `InterStoreTransferService.isScheduleII()` returns the DEA Form 222 message and writes a `Blocked` log entry. No automated transfer is ever attempted for Schedule II.
- **Surplus-source selection** — `InventoryPositionSelector.findSurplusSources()` returns candidates ordered by `Quantity__c DESC`, then `selectBestSource()` filters by cold-chain capability, presence of a DEA registration number, and expiry threshold.
- **Capped transfer math** — `calculateTransferQty()` proposes 50% of the source's surplus above its own safety stock, then caps the result at exactly what the target needs to reach safety stock.
- **Atomic execution with rollback** — `executeTransfer()` deducts from source, adds to target, inserts a `Completed` `Transfer_Log__c`, all inside a `Database.setSavepoint()`/`rollback` boundary with `Security.stripInaccessible(AccessType.UPDATABLE, ...)` for FLS enforcement.
- **Distributor-fallback messaging** — when no eligible source is found, the action returns a `uhText` instructing the ops user to place an emergency order with the primary distributor and contact their district manager.
- **Prompt-template recommendations** — `IST_Inventory_Recommendation` renders a 1–2 sentence per-row recommendation in the Grid using inventory record fields, with rules for Schedule II, critical stock, near-expiry, and healthy stock states.

---

## Architecture

```
+-----------------------------------------------------------------+
|                      AGENTFORCE GRID UI                          |
|     (per-row Transfer/Optimize button + Recommendation column)   |
+-----------------------+-------------------+----------------------+
                        |                   |
       (per-row prompt) |                   | (button click)
                        v                   v
        +-------------------------+  +---------------------------+
        |   IST_Inventory_        |  |  Execute_Inter_Store_     |
        |   Recommendation        |  |  Transfer (Flow)          |
        |   (Prompt Template)     |  |                           |
        +-------------------------+  +-------------+-------------+
                                                    |
                                                    v
                                  +-------------------------------+
                                  |  InterStoreTransferAction      |
                                  |  (@InvocableMethod)            |
                                  +---------------+----------------+
                                                  |
                                                  v
                                  +-------------------------------+
                                  |  InterStoreTransferService     |
                                  |    .evaluate(invId, confirm)   |
                                  +---+------------+--------------++
                                      |            |              |
                                      v            v              v
                          +-------------------+  +---------+  +---------+
                          | InventoryPosition |  | Schema. |  | Database|
                          | Selector          |  | strip   |  | .save-  |
                          | (SOQL only)       |  | Inacces.|  | point() |
                          +-------------------+  +---------+  +---------+
                                  |
                                  v
                  +-----------------+-----------------+----------------+
                  | Inventory_      | Transfer_Log__c | Pharmacy_      |
                  | Position__c     | (audit)         | Store__c       |
                  | (read/update)   |                 | Medication__c  |
                  +-----------------+-----------------+----------------+
```

| Layer | Class / Asset | Responsibility |
|---|---|---|
| UI | Agentforce Grid (record page on `Inventory_Position__c`) | Surfaces critical stock rows; renders per-row prompt output; exposes Transfer/Optimize button. |
| AI | `IST_Inventory_Recommendation` (Prompt Template) | Generates 1–2 sentence row-level recommendation, ≤150 chars, following DEA / stock-level rules. |
| Orchestration | `Execute_Inter_Store_Transfer` (Flow) | Triggered by the Grid button; passes `inventoryPositionId` to the invocable Apex action. |
| Action | `InterStoreTransferAction.execute()` | Invocable entry point. Wraps service result in `ActionOutput` for the agent to consume. |
| Service | `InterStoreTransferService.evaluate()` | All business rules: compliance gate, source selection, qty calc, dry-run vs execute branching, atomic DML. |
| Selector | `InventoryPositionSelector` | All SOQL. `getById()` and `findSurplusSources()`. No DML, no business logic. |
| Data | `Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c`, `Transfer_Log__c` | Domain model. `Transfer_Log__c` is the immutable audit object. |
| Install | `PostInstallScript` (InstallHandler) | Seeds 6 stores, 6 medications, 14 inventory positions; assigns `IST_Ops_User`; verifies prompt template. |

---

## Data Model

### `Pharmacy_Store__c`
Represents a pharmacy store location.

| Field API Name | Type | Required | Notes |
|---|---|---|---|
| `Name` | Text | Yes | Pharmacy Store Name |
| `District__c` | Text(80) | No | Operational district for rollups/routing |
| `Latitude__c` | Number(9,6) | No | Store latitude |
| `Longitude__c` | Number(9,6) | No | Store longitude |
| `Cold_Chain_Capable__c` | Checkbox | No (default `false`) | Drives cold-chain eligibility filter |
| `DEA_Registration__c` | Text(50) | No | Source store must have a non-blank value to be eligible |
| `Is_Active__c` | Checkbox | No (default `true`) | Inactive stores excluded from `findSurplusSources()` |

### `Medication__c`
Represents a medication with regulatory and handling attributes.

| Field API Name | Type | Required | Notes |
|---|---|---|---|
| `Name` | Text | Yes | Medication Name |
| `NDC__c` | Text(30), unique | Yes | National Drug Code, 10/11-digit |
| `DEA_Schedule__c` | Picklist (restricted) | No | Values: `II`, `III`, `IV`, `V`, `None` (default). `II` triggers compliance hard-stop. |
| `Cold_Chain_Required__c` | Checkbox | No (default `false`) | When `true`, only cold-chain-capable source stores are eligible |

### `Inventory_Position__c`
Inventory position of a specific Medication at a specific Pharmacy Store. Auto-number `INV-{000000}`.

| Field API Name | Type | Required | Notes |
|---|---|---|---|
| `Store__c` | Lookup → `Pharmacy_Store__c` | Yes | Restrict on delete |
| `Medication__c` | Lookup → `Medication__c` | Yes | Restrict on delete |
| `Quantity__c` | Number(18,0) | Yes | On-hand quantity |
| `Safety_Stock__c` | Number(18,0) | No | Threshold for replenishment |
| `Expiry_Date__c` | Date | No | Lot expiry date |
| `Recommendation__c` | Long Text Area (32768) | No | Full dry-run recommendation text |
| `Recommendation_Preview__c` | Text(255) | No | Truncated preview — what the Agentforce Grid column actually renders |
| `Status__c` | Formula (Text) | — | `OUT_OF_STOCK` / `LOW` / `HEALTHY` / `UNKNOWN` based on `Quantity__c` vs `Safety_Stock__c` |
| `Status_Color__c` | Formula (Text) | — | `RED` / `ORANGE` / `GREEN` / `GRAY` color code for the status |
| `Store_Name__c` | Formula (Text) | — | `Store__r.Name` flattened for Grid display |
| `Medication_Name__c` | Formula (Text) | — | `Medication__r.Name` flattened for Grid display |

### `Transfer_Log__c`
Immutable audit trail for inter-store transfers and compliance outcomes. Auto-number `TRN-{000000}`.

| Field API Name | Type | Notes |
|---|---|---|
| `Source_Store__c` | Lookup → `Pharmacy_Store__c` | Null on `Blocked` Schedule II logs |
| `Target_Store__c` | Lookup → `Pharmacy_Store__c` | The store with the critical position |
| `Medication__c` | Lookup → `Medication__c` | |
| `Inventory_Position__c` | Lookup → `Inventory_Position__c` | The target position evaluated |
| `Quantity_Transferred__c` | Number(18,0) | `0` for blocked entries |
| `Transfer_Date__c` | DateTime | Set to `DateTime.now()` |
| `Transfer_Status__c` | Picklist (restricted) | `Pending` (default), `Completed`, `Blocked` |
| `Notes__c` | Long Text Area (32768) | Rationale, source/target names, Schedule II block reason |

> Note: per `IST_Ops_User`, this object is **create + read only** — `allowEdit = false`, `allowDelete = false`. That's the intended audit semantic.

---

## Transfer Logic & Constants

The four constants in `InterStoreTransferService` define the entire policy:

| Constant | Value | Effect |
|---|---|---|
| `TRANSFER_BUFFER_PCT` | `50` | Proposed transfer is 50% of source surplus above its safety stock |
| `MIN_DAYS_TO_EXPIRY` | `30` | Source candidates expiring within this window are excluded |
| `DEA_SCHEDULE_II` | `'II'` | Picklist value that triggers the compliance hard-stop |
| `PREVIEW_MAX_LENGTH` | `255` | `Recommendation_Preview__c` cap; longer text is truncated with `...` |

**Quantity calculation** (`calculateTransferQty`):

```
sourceSurplus = source.Quantity__c - source.Safety_Stock__c
targetNeed    = target.Safety_Stock__c - target.Quantity__c
proposed      = sourceSurplus * 50 / 100
qty           = min(proposed, targetNeed)
```

**Worked example** — Mounjaro 5mg at CVS Westside SF (qty=200, safety=50) transferring to CVS Downtown SF (qty=0, safety=50):

- `sourceSurplus = 200 − 50 = 150`
- `targetNeed = 50 − 0 = 50`
- `proposed = 150 × 50 / 100 = 75`
- `qty = min(75, 50) = 50`

The target gets exactly enough to hit its safety stock; the source keeps a 50-unit buffer above its own threshold.

**Eligibility filter order** (`selectBestSource`) — candidates are pre-sorted by `Quantity__c DESC`, so the first one to pass all three checks wins:

1. If `Medication__r.Cold_Chain_Required__c` and `!Store__r.Cold_Chain_Capable__c` → skip
2. If `Store__r.DEA_Registration__c` is blank → skip
3. If `Expiry_Date__c` is set and `today.daysBetween(Expiry_Date__c) < 30` → skip

If every candidate fails, the action returns the distributor-fallback `uhText`.

---

## Demo Scenarios

Ready-to-run anonymous Apex scripts live in `scripts/apex/`. See [scripts/DEMO_PLAYBOOK.md](scripts/DEMO_PLAYBOOK.md) for full instructions.

| Script | Scenario | What It Demonstrates |
|---|---|---|
| `TC1_HappyPath_ColdChainTransfer.apex` | Mounjaro 5mg, cold-chain match, dry-run + execute | Full happy path: surplus selection, cold-chain filter passes, recommendation written, savepoint execution, audit log written |
| `TC2_ScheduleII_ComplianceBlock.apex` | Adderall XR 30mg, Schedule II hard stop | Compliance gate fires before any source search; `Blocked` `Transfer_Log__c` written; DEA Form 222 message returned |
| `TC3_DistributorFallback_NearExpiry.apex` | Ozempic 1mg, only candidate is near-expiry | All candidates fail eligibility; distributor-fallback `uhText` returned; no inventory mutation |

Run with:

```bash
sf apex run --file scripts/apex/TC1_HappyPath_ColdChainTransfer.apex --target-org your-org
```

---

## Setup & Deployment

### Prerequisites

- Salesforce org with **Agentforce enabled** (Prompt Template requires the `AiPrompt` SObject)
- Salesforce CLI (`sf`) installed and authenticated (`sf org login web`)
- API v65.0 (project's declared API version)

### Deploy

```bash
# Deploy the source
sf project deploy start --source-dir force-app --target-org your-org

# Assign the permission set to your user
sf org assign permset --name IST_Ops_User --target-org your-org

# (Optional) seed demo data via the post-install logic, manually
sf apex run --file scripts/apex/TC1_HappyPath_ColdChainTransfer.apex --target-org your-org
```

### Post-deploy steps

1. Verify the prompt template `IST_Inventory_Recommendation` is published (Setup → Prompt Builder).
2. Activate the Flow `Execute_Inter_Store_Transfer` if not already active.
3. On the `Inventory_Position__c` record page (Lightning App Builder), add the Agentforce Grid component and bind:
   - **Recommendation column** → `IST_Inventory_Recommendation` prompt template
   - **Transfer/Optimize button** → `Execute_Inter_Store_Transfer` Flow with input `{Salesforce.Id}` mapped to `inventoryPositionId`
4. Confirm `IST_Ops_User` permission set is assigned to ops users.

If you installed via a managed package, `PostInstallScript.onInstall()` does steps 1, 4, and seeds demo data automatically.

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── InterStoreTransferService.cls       Core service with all business rules
│   ├── InterStoreTransferAction.cls        @InvocableMethod entry for Flow/Agent
│   ├── InventoryPositionSelector.cls       SOQL-only selector
│   ├── ISTTestDataFactory.cls              @IsTest data factory (no test class yet)
│   └── PostInstallScript.cls               InstallHandler — seed + permset
├── objects/
│   ├── Pharmacy_Store__c/
│   ├── Medication__c/
│   ├── Inventory_Position__c/
│   └── Transfer_Log__c/
├── flows/
│   └── Execute_Inter_Store_Transfer.flow-meta.xml
├── prompts/
│   └── IST_Inventory_Recommendation.prompt-meta.xml
├── permissionsets/
│   └── IST_Ops_User.permissionset-meta.xml
└── layouts/
    └── Transfer_Log__c-Transfer Log Layout.layout-meta.xml
```

---

## Known Gaps

Documenting these honestly so contributors know what's missing:

- **No Apex test class yet.** `ISTTestDataFactory` is `@IsTest` and provides `createStore`, `createMedication`, `createInventory` helpers, but there is no `*Test.cls` consumer. To deploy to a production org, you'll need ≥75% coverage; expect to write `InterStoreTransferServiceTest` covering the happy path, Schedule II block, no-eligible-source fallback, near-expiry exclusion, cold-chain mismatch, and savepoint rollback paths.
- **No LWC.** The UI is the standard Agentforce Grid component on the record page — there is no custom Lightning Web Component in this repo.
- **`System.debug()` left in production code.** `InterStoreTransferService` and `InterStoreTransferAction` both have `System.debug('======>...')` calls that should be removed or gated behind a feature flag before a real production deploy.
- **`Recommendation__c` not cleared on execution.** After `executeTransfer()`, only `Recommendation_Preview__c` is overwritten with the completion message; the long-form `Recommendation__c` still holds the pre-execution dry-run text.

---

## Citing This Project

If you use AgentforcePharmaGrid in research, architecture documentation, or a derived implementation, please cite it. See [CITING.md](CITING.md) for full BibTeX, APA, IEEE, and Chicago formats.

GitHub provides a **"Cite this repository"** button in the right sidebar that reads from [CITATION.cff](CITATION.cff).

**Quick BibTeX:**

```bibtex
@software{raju2026agentforcepharmagrid,
  author    = {Raju, Jayavardhan},
  title     = {AgentforcePharmaGrid: Agentforce Grid--Driven Inter-Store Inventory
               Transfers with DEA Compliance and Audit Trail for Salesforce},
  year      = {2026},
  url       = {https://github.com/jayavardhan-raju/AgentforcePharmaGrid},
  version   = {1.0.0}
}
```

A DOI can be registered through Zenodo — see [CITING.md](CITING.md) for the one-time setup.

---

## License

MIT — see `LICENSE` if present, otherwise add one before publishing.

---

## Author

**Jayavardhan Raju** — [@jayavardhan-raju](https://github.com/jayavardhan-raju) · [jayraju.com](https://jayraju.com)
