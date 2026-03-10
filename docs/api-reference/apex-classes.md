---
layout: default
title: Apex Classes
parent: API Reference
nav_order: 1
---

# Apex Class Reference

ApexDox-style documentation for all classes in the Pharmacy IST framework.

---

## InterStoreTransferAction

**Agentforce Invocable Action for inter-store inventory transfer.** Supports dry-run (`confirm=false`) and execution (`confirm=true`). The Grid's Transfer/Optimize button triggers this action. The agent calls it twice per workflow: first for recommendation, then for execution after user confirmation.

**Author:** IST Team
**Since:** API v65.0
**Sharing:** `with sharing`

### Inner Classes

#### ActionInput

Input wrapper passed by Agentforce from the Grid row context.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `inventoryPositionId` | Id | Yes | Salesforce ID of the critical `Inventory_Position__c` record |
| `confirm` | Boolean | No | `false` = dry-run recommendation. `true` = execute transfer. Defaults to `false` if null. |

#### ActionOutput

Output wrapper returned to the Agentforce agent.

| Property | Type | Description |
|----------|------|-------------|
| `success` | Boolean | True if recommendation or execution succeeded; false on compliance/fallback blocks |
| `uhText` | String | Human-readable message for the agent to surface in the Grid conversation |
| `sourceStoreId` | Id | Salesforce ID of the recommended source store |
| `sourceStoreName` | String | Name of the recommended source store |
| `recommendedQty` | Integer | Number of units recommended for transfer |
| `transferLogId` | Id | ID of the `Transfer_Log__c` created on execution (null on dry-run) |

### Methods

#### `execute(List<ActionInput> inputs)` — `@InvocableMethod`

**Label:** Execute Inter-Store Transfer
**Category:** Inventory Management
**Callout:** false

Iterates over inputs (always a list of 1 for single-row Grid actions), delegates to `InterStoreTransferService.evaluate()`, and maps the `TransferResult` to `ActionOutput`.

---

## InterStoreTransferService

**Core service for Inter-Store Transfer operations.** Enforces DEA Schedule II compliance, cold-chain matching, expiry threshold filtering, inventory locking, and atomic DML with audit trail.

**Author:** IST Team
**Since:** API v65.0
**Sharing:** `with sharing`

### Constants

| Constant | Type | Value | Description |
|----------|------|-------|-------------|
| `TRANSFER_BUFFER_PCT` | Integer | 50 | Transfer 50% of source surplus above its safety stock |
| `MIN_DAYS_TO_EXPIRY` | Integer | 30 | Exclude source stock expiring within this many days |
| `DEA_SCHEDULE_II` | String | "II" | DEA Schedule that triggers hard compliance block |
| `PREVIEW_MAX_LENGTH` | Integer | 255 | Max chars for `Recommendation_Preview__c` Grid column |

### Inner Classes

#### TransferResult

Structured result returned to `InterStoreTransferAction`. When `success=false`, `uhText` always contains a next-action directive — never a dead end.

| Property | Type | Description |
|----------|------|-------------|
| `success` | Boolean | Whether the operation succeeded |
| `uhText` | String | Full human-readable text for agent conversation |
| `sourceStoreId` | Id | Recommended source store ID |
| `sourceStoreName` | String | Recommended source store name |
| `recommendedQty` | Integer | Units to transfer |
| `transferLogId` | Id | Transfer log ID (null on dry-run, populated on execution) |

### Public Methods

---

#### `evaluate(Id inventoryPositionId, Boolean confirm)`

**Entry point.** Evaluates and optionally executes an inter-store transfer.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `inventoryPositionId` | Id | Target `Inventory_Position__c` record |
| `confirm` | Boolean | `false` = dry-run, `true` = execute |

**Returns:** `TransferResult`

**Behavior:**
1. Loads target via `InventoryPositionSelector.getById()`
2. Checks DEA Schedule II — if matched, logs compliance block and returns `success=false`
3. Finds surplus source candidates via `InventoryPositionSelector.findSurplusSources()`
4. Applies eligibility filters: cold-chain, DEA registration, expiry threshold
5. If no eligible source, returns distributor fallback with `success=false`
6. Calculates transfer qty: `min(sourceSurplus × 50%, targetNeed)`
7. If `confirm=false`: writes recommendation to record, returns `uhText` with "Shall I proceed?"
8. If `confirm=true`: executes atomic transfer with Savepoint, writes `Transfer_Log__c`

### Private Methods

| Method | Description |
|--------|-------------|
| `isScheduleII(inv)` | Returns true if `medication.DEA_Schedule__c == 'II'` |
| `selectBestSource(target, candidates)` | Filters candidates by cold-chain, DEA registration, and expiry. Returns first eligible (pre-sorted by qty DESC). |
| `calculateTransferQty(target, source)` | Computes `min(sourceSurplus × 50%, targetNeed)` |
| `buildRecommendation(target, source, qty)` | Writes `Recommendation__c` + `Recommendation_Preview__c`, returns dry-run result |
| `executeTransfer(target, source, qty)` | Atomic DML with Savepoint: deduct source, add target, insert `Transfer_Log__c` |
| `logComplianceBlock(inv)` | Inserts `Transfer_Log__c` with status `Blocked` for DEA audit trail |

---

## InventoryPositionSelector

**Selector for Inventory_Position__c — all SOQL for inventory queries.** No DML. No business logic. Only reads. All queries use `WITH USER_MODE`.

**Author:** IST Team
**Since:** API v65.0
**Sharing:** `with sharing`

### Methods

---

#### `getById(Id inventoryPositionId)`

Fetches a single inventory position with full relational context (Store fields: Name, Latitude, Longitude, Cold_Chain_Capable, DEA_Registration, Is_Active; Medication fields: Name, DEA_Schedule, Cold_Chain_Required).

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `inventoryPositionId` | Id | Must not be null |

**Returns:** `Inventory_Position__c` with parent traversals

**Throws:**
- `IllegalArgumentException` if `inventoryPositionId` is null
- `QueryException` if record not found

---

#### `findSurplusSources(Id medicationId, Id excludeStoreId, Integer minimumSurplus)`

Finds candidate source stores with surplus of a given medication, excluding the target store. Orders by quantity descending (most surplus first). Only includes active stores.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `medicationId` | Id | Medication to match |
| `excludeStoreId` | Id | Target store to exclude from candidates |
| `minimumSurplus` | Integer | Minimum quantity threshold (defaults to 1 if null) |

**Returns:** `List<Inventory_Position__c>` with Store and Medication parent fields

---

## ISTTestDataFactory

**Shared test data factory for all IST test classes.** Provides reusable methods to create stores, medications, and inventory positions with minimal boilerplate.

**Test Only:** `@IsTest`

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `createStore(name, coldChain, deaReg, active)` | `Pharmacy_Store__c` | Inserts and returns a store with District 1, SF coordinates |
| `createMedication(name, deaSchedule, coldChain)` | `Medication__c` | Inserts and returns a medication with auto-generated NDC |
| `createInventory(storeId, medId, qty, safetyStock, daysToExpiry)` | `Inventory_Position__c` | Inserts and returns an inventory position with computed expiry date |
