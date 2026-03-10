---
layout: default
title: Architecture Overview
parent: Architecture
nav_order: 1
---

# Architecture Overview

Pharmacy IST follows an **Action → Service → Selector** pattern, with Agentforce orchestration layered above through a Flow and agent script.

---

## Layered Design

```
┌───────────────────────────────────────────────────────────┐
│                   AGENTFORCE LAYER                         │
│   Agent Script (inventory_transfer_ops_agent)              │
│   Prompt Template (IST Inventory Recommendation)           │
└─────────────────────────┬─────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────┐
│                     FLOW LAYER                             │
│   Execute_Inter_Store_Transfer (Auto-Launched Flow)        │
│   Bridges Agentforce to Apex via Invocable Action          │
└─────────────────────────┬─────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────┐
│                  INVOCABLE ACTION                          │
│   InterStoreTransferAction                                 │
│   @InvocableMethod — ActionInput / ActionOutput wrappers   │
│   Zero logic — delegates everything to Service             │
└─────────────────────────┬─────────────────────────────────┘
                          │
┌─────────────────────────▼─────────────────────────────────┐
│                    SERVICE LAYER                            │
│   InterStoreTransferService                                │
│   evaluate() → isScheduleII() → selectBestSource()         │
│   calculateTransferQty() → buildRecommendation()           │
│   executeTransfer() → logComplianceBlock()                 │
└──────────┬────────────────────────────────────────────────┘
           │
┌──────────▼────────────────────────────────────────────────┐
│                   SELECTOR LAYER                           │
│   InventoryPositionSelector                                │
│   getById() — single record with full relational context   │
│   findSurplusSources() — candidate sources, qty DESC       │
│   ALL SOQL, zero DML, zero business logic                  │
└───────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

### Agentforce Layer
The agent script (`inventory_transfer_ops_agent`) manages conversation state with five mutable variables: `inventory_position_id`, `dry_run_success`, `recommended_qty`, `source_store_name`, `uh_text`, and `confirmed`. The prompt template (`IST Inventory Recommendation`) provides AI-generated status summaries for the Grid column using Einstein prompt merge fields.

### Flow Layer
`Execute_Inter_Store_Transfer` is an Auto-Launched Flow at API v65.0. It accepts `inventoryPositionId` (String) and `confirm` (Boolean) as inputs, invokes `InterStoreTransferAction` as an Apex action, and outputs `success`, `uhText`, `sourceStoreId`, `sourceStoreName`, `recommendedQty`, and `transferLogId`. A `refreshView` assignment forces the Grid to reload after execution.

### Invocable Action Layer
`InterStoreTransferAction` provides the `@InvocableMethod` interface that Agentforce calls. It contains `ActionInput` and `ActionOutput` inner classes with `@InvocableVariable` annotations. The method iterates over inputs (always a list of 1 for single-row Grid actions), delegates to `InterStoreTransferService.evaluate()`, and maps the `TransferResult` to `ActionOutput`.

### Service Layer
`InterStoreTransferService` owns all business logic. It enforces the compliance gate, finds and filters source candidates, calculates transfer quantities, builds dry-run recommendations (writing to `Recommendation__c` and `Recommendation_Preview__c`), and executes atomic transfers with Savepoint-based rollback. Contains zero SOQL — all queries go through the Selector.

### Selector Layer
`InventoryPositionSelector` encapsulates all SOQL. Both methods use `WITH USER_MODE` for record-level security enforcement. `getById()` loads a single inventory position with full parent traversals (Store fields, Medication fields). `findSurplusSources()` finds active stores with surplus stock, ordered by quantity descending.

---

## End-to-End Data Flow

1. **Grid row action** — Operator clicks "Transfer/Optimize" on a critical stock row in the Agentforce Grid
2. **Agent receives context** — The agent script receives `inventory_position_id` from Grid context and routes to `Transfer_Evaluation` topic
3. **Dry-run call** — Agent invokes `Execute_Inter_Store_Transfer` flow with `confirm=false`
4. **Flow → Action → Service** — Flow calls `InterStoreTransferAction`, which delegates to `InterStoreTransferService.evaluate()`
5. **Compliance check** — If Schedule II, hard block fires immediately. `Transfer_Log__c` (Blocked) is written. `success=false` returned.
6. **Source search** — Selector finds surplus sources. Service filters by cold-chain, DEA registration, and expiry threshold.
7. **Recommendation** — If eligible source found, calculates qty, writes `Recommendation__c` and `Recommendation_Preview__c`, returns `uhText` with "Shall I proceed?"
8. **Agent surfaces result** — Agent displays `uhText` verbatim. If `success=false`, no confirmation prompt is offered.
9. **User confirms** — Operator says "yes" / "proceed" / "confirm"
10. **Execute call** — Agent invokes the flow again with `confirm=true`
11. **Atomic execution** — Savepoint set. Source qty deducted, target qty added, `Transfer_Log__c` (Completed) written. Any failure → full rollback.
12. **Grid refresh** — Flow sets `refreshView=true`, Grid reloads with updated quantities

---

## Security Model

The system enforces security at every layer:

- **Record-level**: All classes use `with sharing`. Selector queries use `WITH USER_MODE`.
- **Field-level**: `Security.stripInaccessible(AccessType.UPDATABLE)` before update DML. Schema `isUpdateable()` / `isCreateable()` checks before DML.
- **Object-level**: Permission set `IST_Ops_User` grants CRUD on operational objects. `Transfer_Log__c` is intentionally create/read only — no edit or delete — preserving audit immutability.
- **Transaction safety**: `Database.setSavepoint()` with rollback on any exception during execution.
