---
layout: default
title: Architecture Overview
parent: Architecture
nav_order: 1
---

# Architecture Overview

AgentforceGrid follows a clean **Action → Service → Selector** layered architecture with no triggers. Each layer has a single responsibility, and dependencies flow strictly downward.

---

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      AGENTFORCE GRID UI                         │
│              (Inventory_Position__c List View)                   │
│         Ops user clicks "Transfer/Optimize" on a row            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              Execute_Inter_Store_Transfer (Flow)                 │
│         AutoLaunchedFlow — passes inventoryPositionId            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InterStoreTransferAction (Invocable Action)            │
│   @InvocableMethod — thin adapter, maps ActionInput/Output       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InterStoreTransferService (Service Layer)              │
│   Core business logic: compliance, selection, execution          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InventoryPositionSelector (Selector Layer)             │
│   Read-only SOQL with USER_MODE enforcement                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

| Layer | Class | Responsibility |
|-------|-------|----------------|
| **Flow** | `Execute_Inter_Store_Transfer` | Agentforce entry point. Receives `inventoryPositionId` and `confirm` as input variables, invokes the Apex action, and sets `refreshView = true` to refresh the Grid after completion. |
| **Action** | `InterStoreTransferAction` | `@InvocableMethod` adapter. Defines `ActionInput` and `ActionOutput` inner classes with `@InvocableVariable` annotations for Agentforce. Iterates over inputs (always a list of 1 for single-row actions), delegates each to `InterStoreTransferService.evaluate()`, and maps the `TransferResult` to `ActionOutput`. Contains zero business logic. |
| **Service** | `InterStoreTransferService` | All business logic. Performs DEA Schedule II compliance gate, finds and filters source store candidates, calculates transfer quantities, writes dry-run recommendations to `Recommendation__c` and `Recommendation_Preview__c`, executes atomic transfers with `Database.setSavepoint()`, writes `Transfer_Log__c` audit records, and enforces CRUD/FLS. |
| **Selector** | `InventoryPositionSelector` | All SOQL queries. `getById()` fetches a single inventory position with full relational context (Store + Medication fields). `findSurplusSources()` finds candidate source stores sorted by quantity descending, filtered to active stores with surplus above the target's safety stock. All queries use `WITH USER_MODE`. |

---

## End-to-End Data Flow

### Step 1: Dry-Run (confirm = false)

1. Ops user clicks "Transfer/Optimize" on a critical row in the Agentforce Grid
2. `Execute_Inter_Store_Transfer` flow fires with the row's `inventoryPositionId`
3. `InterStoreTransferAction.execute()` receives the input, sets `confirm = false`
4. `InterStoreTransferService.evaluate()` loads the target inventory position via `InventoryPositionSelector.getById()`
5. **Compliance gate**: If `Medication__r.DEA_Schedule__c == 'II'`, a hard stop is returned with a compliance block audit log — no source search occurs
6. `InventoryPositionSelector.findSurplusSources()` queries for all candidate source stores with surplus
7. `selectBestSource()` filters candidates by cold-chain capability, DEA registration, and expiry threshold (≥ 30 days)
8. `calculateTransferQty()` computes 50% of source surplus, capped at target need
9. `buildRecommendation()` writes the full recommendation to `Recommendation__c` (Long Text Area) and a truncated version to `Recommendation_Preview__c` (Text 255 for Grid display)
10. The agent surfaces `uhText` in the conversation: "Transfer Recommendation for [med] at [store]... Shall I proceed?"

### Step 2: Execution (confirm = true)

1. Ops user confirms via the agent conversation
2. Same flow fires with `confirm = true`
3. `InterStoreTransferService.evaluate()` re-evaluates the same position (re-checks compliance, re-selects source)
4. `executeTransfer()` sets a `Database.setSavepoint()`
5. Source `Inventory_Position__c.Quantity__c` is decremented
6. Target `Inventory_Position__c.Quantity__c` is incremented
7. `Recommendation_Preview__c` is updated with completion status
8. `Security.stripInaccessible()` is applied to the update list
9. An immutable `Transfer_Log__c` record is inserted with status `'Completed'`
10. On any exception, `Database.rollback(sp)` ensures zero partial updates
11. The agent surfaces: "Transfer Executed Successfully... Audit trail recorded."

---

## Security Model

| Mechanism | Implementation |
|-----------|---------------|
| **Sharing** | All Apex classes declare `with sharing` — record-level access is enforced by the running user's sharing rules |
| **SOQL Security** | All queries use `WITH USER_MODE` — the query respects the user's CRUD and FLS permissions |
| **CRUD Checks** | `Schema.sObjectType.Inventory_Position__c.isUpdateable()` and `Schema.sObjectType.Transfer_Log__c.isCreateable()` are verified before DML |
| **FLS Enforcement** | `Security.stripInaccessible(AccessType.UPDATABLE, ...)` strips fields the user cannot edit before inventory position updates |
| **Audit Immutability** | The `IST_Ops_User` permission set grants only Create + Read on `Transfer_Log__c` — no Edit or Delete — making the audit trail tamper-proof at the permission level |
| **Compliance Logging** | Even denied Schedule II requests write a `Transfer_Log__c` with `Transfer_Status__c = 'Blocked'` for DEA audit trail |
