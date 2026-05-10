---
layout: default
title: Architecture Overview
parent: Architecture
nav_order: 1
has_children: false
---

# Architecture Overview

AgentforcePharmaGrid follows a strict **Service / Selector / Invocable Action** pattern. There are no triggers, no batch jobs, no LWCs, and no callouts. Every action is initiated synchronously from the Agentforce Grid's per-row button.

---

## Layered Architecture

```
+-----------------------------------------------------------------+
|  AGENTFORCE GRID  (record page on Inventory_Position__c)        |
|                                                                  |
|   +---------------+   +-------------+   +----------------+       |
|   | Status / qty  |   | Recommen-   |   | Transfer/      |       |
|   | columns       |   | dation col  |   | Optimize btn   |       |
|   +-------+-------+   +------+------+   +--------+-------+       |
+-----------+------------------|--------------------|--------------+
            |                  |                    |
       (read SOQL)       (per-row prompt)    (button click)
            |                  |                    |
            |                  v                    v
            |       +-------------------+  +---------------------+
            |       | IST_Inventory_    |  | Execute_Inter_      |
            |       | Recommendation    |  | Store_Transfer Flow |
            |       | (Prompt Template) |  +----------+----------+
            |       +-------------------+             |
            |                                         v
            |                          +--------------------------+
            |                          | InterStoreTransferAction |
            |                          | @InvocableMethod         |
            |                          +-------------+------------+
            |                                        |
            v                                        v
   +-----------------+              +-------------------------------+
   | Inventory_      |              |  InterStoreTransferService    |
   | Position__c     |              |  (all business rules)         |
   +-----------------+              +---+----------------+----------+
                                        |                |
                              (SOQL via)|                |(DML inside savepoint)
                                        v                v
                          +-------------------+  +-----------------+
                          | InventoryPosition |  | Inventory_      |
                          | Selector          |  | Position__c     |
                          +-------------------+  | Transfer_Log__c |
                                                 +-----------------+
```

| Layer | Asset | Responsibility |
|---|---|---|
| UI | Agentforce Grid | Renders rows; binds prompt template + button |
| AI | `IST_Inventory_Recommendation` | Generates per-row recommendation text (≤150 chars) |
| Orchestration | `Execute_Inter_Store_Transfer` Flow | Bridges Grid button click → Apex invocable |
| Action | `InterStoreTransferAction` | Wraps service call as `@InvocableMethod` for Flow/Agent |
| Service | `InterStoreTransferService` | Compliance gate, source selection, qty math, atomic DML |
| Selector | `InventoryPositionSelector` | All SOQL; no DML; no business logic |
| Data | `Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c`, `Transfer_Log__c` | Domain model + audit |

---

## End-to-End Data Flow

### Recommendation generation (every row, every time the Grid renders)

1. Grid renders rows from `Inventory_Position__c`.
2. For each row, the Grid renders the **Recommendation column** by calling the `IST_Inventory_Recommendation` prompt template with the row record's merge fields.
3. The prompt template's hard-coded rules return one of: Schedule II message, critical-stock message, healthy message, or expiry-prefixed variant. Output is plain text, ≤150 chars.

> The prompt template output is **not** persisted to `Recommendation__c`. It's rendered live each time. `Recommendation__c` and `Recommendation_Preview__c` are only written by `InterStoreTransferService.buildRecommendation()` after the Transfer/Optimize button is clicked.

### Transfer evaluation and execution (button click)

1. User clicks **Transfer/Optimize** on a Grid row.
2. The Grid invokes `Execute_Inter_Store_Transfer` Flow with input `inventoryPositionId = {Salesforce.Id}` and `confirm = false`.
3. Flow calls `InterStoreTransferAction.execute(List<ActionInput>)`.
4. The action calls `InterStoreTransferService.evaluate(inventoryPositionId, confirm=false)`.
5. Service path:
   - **Load** target position via `InventoryPositionSelector.getById()` (one SOQL).
   - **Compliance gate**: if `Medication__r.DEA_Schedule__c == 'II'` → write `Blocked` Transfer Log, return DEA Form 222 message. **Stop.**
   - **Find candidates** via `InventoryPositionSelector.findSurplusSources()`, ordered by `Quantity__c DESC`.
   - **Filter** via `selectBestSource()`: cold-chain, DEA registration present, ≥30 days to expiry.
   - **No source** → return distributor-fallback `uhText`. **Stop.**
   - **Calculate qty** via `calculateTransferQty()`.
   - **Dry-run path** (`confirm=false`): write `Recommendation__c` + `Recommendation_Preview__c`, return `uhText` ending in *"Shall I proceed with this transfer?"*.
6. Agent surfaces the dry-run text. User confirms. The agent calls the same action with `confirm = true`.
7. Service `executeTransfer()` path:
   - `Database.setSavepoint()`
   - CRUD/FLS gate (`Schema.sObjectType.X.isUpdateable()` / `isCreateable()`)
   - Build source-deduct + target-add update records
   - Build `Transfer_Log__c` with status `Completed`
   - `Security.stripInaccessible(AccessType.UPDATABLE, ...)` then `update`
   - `insert` the log
   - On any exception: `Database.rollback(sp)` and return rollback message
8. Action wraps the `TransferResult` in `ActionOutput` and returns to the Flow / Agent.

---

## Security Model

| Layer | Mechanism |
|---|---|
| Sharing | All Apex classes declared `with sharing` |
| SOQL | `WITH SECURITY_ENFORCED` on every query in `InventoryPositionSelector` |
| CRUD | `Schema.sObjectType.X.isUpdateable()` / `isCreateable()` checked before DML in `executeTransfer()` and `logComplianceBlock()` |
| FLS | `Security.stripInaccessible(AccessType.UPDATABLE, ...)` applied to update records before DML |
| Permissions | `IST_Ops_User` permission set grants object access; `Transfer_Log__c` is **create + read only** (no edit, no delete) for audit immutability |
| Atomic DML | `Database.setSavepoint()` / `Database.rollback()` on any exception in `executeTransfer()` |

---

## Compliance & Audit

`Transfer_Log__c` is the system of record for all transfer activity, including denied requests:

- **`Completed`** — written by `executeTransfer()` after a successful transfer, with `Source_Store__c`, `Target_Store__c`, `Medication__c`, `Inventory_Position__c`, `Quantity_Transferred__c`, `Transfer_Date__c`, and a detailed `Notes__c` string.
- **`Blocked`** — written by `logComplianceBlock()` when a Schedule II request is intercepted. `Source_Store__c` is null (no source was searched), `Quantity_Transferred__c = 0`, and `Notes__c` contains the DEA Form 222 reason.
- **`Pending`** — the picklist default. Not written by current code paths but available for future workflows.

Because the permission set denies edit and delete on `Transfer_Log__c`, audit records are effectively immutable for ops users.
