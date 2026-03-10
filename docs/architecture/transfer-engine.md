---
layout: default
title: Transfer Engine
parent: Architecture
nav_order: 3
---

# Transfer Engine

The transfer engine in `InterStoreTransferService` implements the full decision tree for evaluating and executing inter-store inventory transfers.

---

## Decision Tree

```
evaluate(inventoryPositionId, confirm)
│
├─ 1. Load target → InventoryPositionSelector.getById()
│     └─ Not found? → Return error: "Unable to locate Inventory Position"
│
├─ 2. DEA Schedule II check → isScheduleII()
│     └─ YES → logComplianceBlock() → Return:
│              success=false
│              "Schedule II controlled substance detected...
│               Manual DEA Form 222 required...
│               No automated transfer initiated."
│              *** NO "Shall I proceed?" prompt ***
│
├─ 3. Find sources → InventoryPositionSelector.findSurplusSources()
│     Filters: same medication, different store, qty > target safety stock + 1, active store
│     Sorted: Quantity DESC (most surplus first)
│
├─ 4. Eligibility filters → selectBestSource()
│     For each candidate (in qty DESC order):
│       ├─ Cold-chain needed but store not capable? → Skip
│       ├─ No DEA registration on file? → Skip
│       ├─ Expiry within 30 days? → Skip
│       └─ All checks pass → This is the best source
│
├─ 5. No eligible source? → Return:
│     success=false
│     "No suitable source store found... 
│      Place emergency order with distributor...
│      Contact district manager."
│     *** NO "Shall I proceed?" prompt ***
│
├─ 6. Calculate quantity → calculateTransferQty()
│     sourceSurplus = source.Quantity - source.Safety_Stock
│     targetNeed    = target.Safety_Stock - target.Quantity
│     proposed      = sourceSurplus × 50%
│     transferQty   = min(proposed, targetNeed)
│
├─ 7. confirm = false? → buildRecommendation()
│     Write Recommendation__c (full text) + Recommendation_Preview__c (≤255 chars)
│     Return: success=true, uhText with "Shall I proceed?"
│
└─ 8. confirm = true? → executeTransfer()
      Savepoint set
      ├─ CRUD checks (isUpdateable, isCreateable)
      ├─ Deduct qty from source
      ├─ Add qty to target + update Recommendation_Preview__c
      ├─ stripInaccessible before update
      ├─ Insert Transfer_Log__c (Completed)
      └─ Return: success=true, uhText with log reference + timestamp
      On ANY exception → Database.rollback(sp), return error
```

---

## Compliance Gate: Schedule II

The DEA Schedule II check is the **first** gate in the evaluation pipeline. It fires before any source search, ensuring zero network queries are wasted on non-transferable medications.

When triggered:
1. A `Transfer_Log__c` record is inserted with `Transfer_Status__c = 'Blocked'` and `Quantity_Transferred__c = 0`
2. The `Notes__c` field records the compliance block reason
3. `success=false` is returned — the agent script recognizes this and does NOT offer a "Proceed?" prompt
4. The `uhText` directs the user to contact their DEA compliance officer for a manual Form 222 transfer

This creates an auditable record of every attempted Schedule II transfer, even denied ones, satisfying DEA audit requirements.

---

## Source Eligibility Filters

Candidates are pre-filtered by the Selector query (same medication, different store, surplus above safety stock + 1, active store). The Service then applies three additional eligibility checks in `selectBestSource()`:

| Filter | Check | Impact |
|--------|-------|--------|
| **Cold-Chain** | `medication.Cold_Chain_Required__c = true` AND `store.Cold_Chain_Capable__c = false` | Candidate skipped |
| **DEA Registration** | `store.DEA_Registration__c` is blank | Candidate skipped |
| **Expiry Threshold** | `Date.today().daysBetween(candidate.Expiry_Date__c) < 30` | Candidate skipped |

Because candidates arrive sorted by `Quantity__c DESC`, the first candidate to pass all three filters is the best available source (highest surplus).

---

## Quantity Calculation

The formula ensures the target gets what it needs without draining the source below its own safety stock:

```
Source Surplus  = source.Quantity__c - source.Safety_Stock__c
Target Need     = target.Safety_Stock__c - target.Quantity__c
Proposed Qty    = Source Surplus × (TRANSFER_BUFFER_PCT / 100)
                = Source Surplus × 50%
Transfer Qty    = min(Proposed Qty, Target Need)
```

**Example:** Source has 200 units, safety stock 50. Target has 0 units, safety stock 50.

```
Source Surplus  = 200 - 50 = 150
Target Need     = 50 - 0 = 50
Proposed        = 150 × 50% = 75
Transfer Qty    = min(75, 50) = 50 units
```

The target gets exactly what it needs to reach safety stock. The source retains 150 units (200 - 50), well above its own safety stock.

---

## Recommendation Fields

The dry-run recommendation is written to two fields on the target `Inventory_Position__c`:

| Field | Type | Purpose |
|-------|------|---------|
| `Recommendation__c` | Long Text Area (32KB) | Full recommendation text. Visible on record detail page. |
| `Recommendation_Preview__c` | Text(255) | Truncated preview (appends "..." if over 255 chars). Displayed in Agentforce Grid column. |

The dual-field approach exists because Long Text Area fields are not supported as Agentforce Grid columns. The preview field ensures the recommendation is visible directly in the Grid without navigating to the record.

---

## Atomic Execution

When `confirm=true`, the execution is wrapped in a `Database.setSavepoint()`:

1. **CRUD checks** — Verifies `isUpdateable()` on `Inventory_Position__c` and `isCreateable()` on `Transfer_Log__c`
2. **Source deduction** — New `Inventory_Position__c` with reduced `Quantity__c`
3. **Target addition** — New `Inventory_Position__c` with increased `Quantity__c` and completion message in `Recommendation_Preview__c`
4. **FLS enforcement** — `Security.stripInaccessible(AccessType.UPDATABLE)` on both update records
5. **Audit log** — `Transfer_Log__c` insert with status `Completed`, source/target details, medication, quantity, and timestamp
6. **Rollback** — Any exception triggers `Database.rollback(sp)` and returns `success=false` with error message

---

## Tuning Parameters

| Constant | Value | Location | Effect |
|----------|-------|----------|--------|
| `TRANSFER_BUFFER_PCT` | 50 | `InterStoreTransferService` | Percentage of source surplus to transfer. Lower = more conservative. |
| `MIN_DAYS_TO_EXPIRY` | 30 | `InterStoreTransferService` | Days-to-expiry threshold. Sources below this are excluded. |
| `DEA_SCHEDULE_II` | "II" | `InterStoreTransferService` | Schedule value that triggers hard compliance block. |
| `PREVIEW_MAX_LENGTH` | 255 | `InterStoreTransferService` | Max chars for Grid column preview. Matches `Recommendation_Preview__c` field length. |
