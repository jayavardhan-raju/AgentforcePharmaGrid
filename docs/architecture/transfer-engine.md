---
layout: default
title: Transfer Engine
parent: Architecture
nav_order: 3
---

# Transfer Engine

The transfer engine is the core algorithm in `InterStoreTransferService` that determines which source store to use, how many units to transfer, and whether the transfer is compliant.

---

## Decision Flow

```
                    ┌───────────────────────┐
                    │  evaluate() called     │
                    │  with positionId +     │
                    │  confirm flag          │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Load target via       │
                    │  getById()             │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐     YES    ┌──────────────────┐
                    │  DEA Schedule II?      │──────────▶│ HARD STOP        │
                    │  (medication check)    │           │ Log compliance   │
                    └───────────┬───────────┘           │ block, return    │
                                │ NO                    │ DEA Form 222 msg │
                                ▼                       └──────────────────┘
                    ┌───────────────────────┐
                    │  findSurplusSources() │
                    │  Query candidate       │
                    │  source stores         │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  selectBestSource()   │
                    │  Filter by:            │
                    │  • Cold chain          │
                    │  • DEA registration    │
                    │  • Expiry ≥ 30 days    │
                    └───────────┬───────────┘
                                │
                       ┌────────┴────────┐
                       │                 │
                  No source         Source found
                       │                 │
                       ▼                 ▼
              ┌────────────────┐  ┌───────────────────┐
              │ FALLBACK       │  │ calculateTransfer  │
              │ Recommend      │  │ Qty()              │
              │ distributor    │  └─────────┬─────────┘
              │ order          │            │
              └────────────────┘   ┌───────┴───────┐
                                   │               │
                            confirm=false    confirm=true
                                   │               │
                                   ▼               ▼
                          ┌──────────────┐ ┌──────────────────┐
                          │ DRY-RUN      │ │ EXECUTE          │
                          │ Write reco   │ │ Savepoint        │
                          │ to record    │ │ Deduct source    │
                          │ Return uhText│ │ Add to target    │
                          │ "Shall I     │ │ Write log        │
                          │  proceed?"   │ │ Rollback on fail │
                          └──────────────┘ └──────────────────┘
```

---

## Compliance Gate: DEA Schedule II

The compliance check is the **first** thing that runs after loading the target. It has the highest priority and cannot be bypassed — not even by `confirm = true`.

**Logic:** If `target.Medication__r.DEA_Schedule__c == 'II'`, the transfer is immediately blocked.

**Behavior:**
- No source store search is performed
- No confirmation prompt is surfaced
- A `Transfer_Log__c` record is written with `Transfer_Status__c = 'Blocked'` and `Quantity_Transferred__c = 0`
- The agent returns a message directing the ops user to their DEA compliance officer and citing the DEA Form 222 requirement
- `confirm = true` does **not** bypass this check (verified by test `testEvaluate_ScheduleII_ConfirmTrue_StillBlocked`)

---

## Source Selection Algorithm

### Pre-filtering (SOQL)

`InventoryPositionSelector.findSurplusSources()` returns candidates matching:

| Condition | Enforced In |
|-----------|-------------|
| Same medication (`Medication__c = :medicationId`) | SOQL WHERE |
| Different store (`Store__c != :excludeStoreId`) | SOQL WHERE |
| Quantity above minimum (`Quantity__c > :minQty`) where minQty = target's safety stock + 1 | SOQL WHERE |
| Active store (`Store__r.Is_Active__c = true`) | SOQL WHERE |
| Sorted by `Quantity__c DESC` | SOQL ORDER BY |

### Post-filtering (Apex)

`selectBestSource()` iterates through the pre-sorted candidates and applies:

| Rule | Check | Skip If |
|------|-------|---------|
| **Cold chain** | `target.Medication__r.Cold_Chain_Required__c` | Source `Store__r.Cold_Chain_Capable__c = false` |
| **DEA registration** | Always checked | Source `Store__r.DEA_Registration__c` is blank |
| **Expiry threshold** | `candidate.Expiry_Date__c` checked | Days to expiry < `MIN_DAYS_TO_EXPIRY` (30 days) |

The **first** candidate that passes all three checks is selected (highest quantity due to pre-sorting).

---

## Quantity Calculation

### Formula

```
sourceSurplus = source.Quantity__c − source.Safety_Stock__c
targetNeed    = target.Safety_Stock__c − target.Quantity__c
proposed      = sourceSurplus × (TRANSFER_BUFFER_PCT / 100)
                                  ↓
                                 50%
transferQty   = MIN(proposed, targetNeed)
```

### Design Rationale

| Parameter | Value | Why |
|-----------|-------|-----|
| `TRANSFER_BUFFER_PCT` | 50 | Prevents destabilizing the source store — only half the surplus is transferred, keeping the source well above its own safety stock |
| Cap at `targetNeed` | Dynamic | Prevents over-supplying the target — the transfer brings the target exactly to its safety stock, not above |

### Worked Examples

**Example 1: Standard transfer**

| Variable | Source Store | Target Store |
|----------|-------------|-------------|
| Quantity | 200 | 0 |
| Safety Stock | 50 | 50 |
| Surplus/Need | 150 (surplus) | 50 (need) |
| Proposed (50%) | 75 | — |
| **Transfer Qty** | **50** (capped at target need) | |

**Example 2: Limited surplus**

| Variable | Source Store | Target Store |
|----------|-------------|-------------|
| Quantity | 80 | 10 |
| Safety Stock | 50 | 50 |
| Surplus/Need | 30 (surplus) | 40 (need) |
| Proposed (50%) | 15 | — |
| **Transfer Qty** | **15** (surplus-limited) | |

---

## Constants Reference

| Constant | Value | Type | Description |
|----------|-------|------|-------------|
| `TRANSFER_BUFFER_PCT` | `50` | Integer | Percentage of source surplus to transfer |
| `MIN_DAYS_TO_EXPIRY` | `30` | Integer | Source stock expiring within this many days is excluded |
| `DEA_SCHEDULE_II` | `'II'` | String | DEA Schedule value that triggers the compliance hard stop |
| `PREVIEW_MAX_LENGTH` | `255` | Integer | Max characters for `Recommendation_Preview__c` (Text field limit for Agentforce Grid column) |

---

## Recommendation Fields

The dry-run writes two fields on the target `Inventory_Position__c`:

| Field | Type | Purpose |
|-------|------|---------|
| `Recommendation__c` | Long Text Area (32768) | Full recommendation text, visible on the record detail page |
| `Recommendation_Preview__c` | Text (255) | Truncated version for the Agentforce Grid column — Long Text Area fields are **not supported** as Grid columns, so this Text(255) field exists as a workaround |

If the full `uhText` exceeds 255 characters, the preview is truncated to 252 characters with `'...'` appended.

After execution (`confirm = true`), `Recommendation_Preview__c` is overwritten with a completion status message (e.g., "Transfer completed: 50 units from CVS Westside. See Transfer Log for details.").
