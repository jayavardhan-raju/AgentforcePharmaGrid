---
layout: default
title: Apex Classes
parent: API Reference
nav_order: 1
---

# Apex API Reference

Complete ApexDox-style documentation for all Apex classes in the AgentforceGrid project.

---

## InterStoreTransferAction

**Agentforce Invocable Action: Execute Inter-Store Transfer. Supports dry-run (`confirm=false`) and execution (`confirm=true`). The Grid's Transfer/Optimize button triggers this action. The agent calls it twice per workflow: first for recommendation, then for execution.**

**Author:** IST Team  
**Since:** API v65.0  
**Sharing:** `with sharing`

### Inner Classes

#### ActionInput

Input wrapper — Agentforce passes these from the Grid row context.

| Property | Type | Required | Label | Description |
|----------|------|----------|-------|-------------|
| `inventoryPositionId` | `Id` | Yes | Inventory Position ID | The Salesforce ID of the critical `Inventory_Position__c` record |
| `confirm` | `Boolean` | No | Confirm Transfer | `false` = dry-run recommendation only. `true` = execute the transfer. Defaults to `false` when null. |

#### ActionOutput

Output wrapper — returned to the Agentforce agent.

| Property | Type | Label | Description |
|----------|------|-------|-------------|
| `success` | `Boolean` | Success | `true` if recommendation or execution succeeded; `false` on compliance/fallback blocks |
| `uhText` | `String` | UH Text | Human-readable message for the agent to surface in the Grid conversation |
| `sourceStoreId` | `Id` | Source Store ID | Salesforce ID of the recommended source store |
| `sourceStoreName` | `String` | Source Store Name | Name of the recommended source store |
| `recommendedQty` | `Integer` | Recommended Quantity | Number of units recommended for transfer |
| `transferLogId` | `Id` | Transfer Log ID | ID of the `Transfer_Log__c` record created on execution (null on dry-run) |

### Public Methods

#### `execute(List<ActionInput> inputs)`

**Invocable entry point called by Agentforce.**

**Annotations:**
- `@InvocableMethod(label='Execute Inter-Store Transfer', description='Recommends (dry-run) or executes an inter-store inventory transfer for a critical stock row. Schedule II drugs are automatically blocked. Returns uhText for agent to surface.', category='Inventory Management', callout=false)`

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `inputs` | `List<ActionInput>` | List of action inputs (Agentforce always passes a list of 1 for single-row actions) |

**Returns:** `List<ActionOutput>` — One output per input with success flag, uhText, source details, and transfer log ID.

**Behavior:**
1. Iterates over the input list
2. For each input, defaults `confirm` to `false` if null
3. Delegates to `InterStoreTransferService.evaluate(inventoryPositionId, confirmFlag)`
4. Maps the `TransferResult` fields to `ActionOutput` fields
5. Returns the output list

---

## InterStoreTransferService

**Core service for Inter-Store Transfer (IST) operations. Enforces: DEA Schedule II compliance, cold-chain matching, inventory locking, and atomic DML with audit trail.**

**Author:** IST Team  
**Since:** API v65.0  
**Sharing:** `with sharing`

### Constants

| Constant | Type | Value | Description |
|----------|------|-------|-------------|
| `TRANSFER_BUFFER_PCT` | `Integer` | `50` | Transfer 50% of source surplus above its own safety stock |
| `MIN_DAYS_TO_EXPIRY` | `Integer` | `30` | Source stock expiring within this many days is excluded from transfer |
| `DEA_SCHEDULE_II` | `String` | `'II'` | DEA Schedule that triggers a hard compliance block |
| `PREVIEW_MAX_LENGTH` | `Integer` | `255` | Max length of Text(255) `Recommendation_Preview__c` Grid column |

### Inner Classes

#### TransferResult

Structured result returned to `InterStoreTransferAction`. `success=false` always includes a next action in `uhText` — never a dead end.

| Property | Type | Description |
|----------|------|-------------|
| `success` | `Boolean` | Whether the operation succeeded |
| `uhText` | `String` | Full human-readable text shown in agent conversation |
| `sourceStoreId` | `Id` | Salesforce ID of the recommended/used source store |
| `sourceStoreName` | `String` | Name of the source store |
| `recommendedQty` | `Integer` | Number of units recommended/transferred |
| `transferLogId` | `Id` | ID of the `Transfer_Log__c` created on execution (null on dry-run) |

**Constructor:** `TransferResult(Boolean success, String uhText)`

### Public Methods

#### `evaluate(Id inventoryPositionId, Boolean confirm)`

**Evaluate and optionally execute an inter-store transfer.**

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `inventoryPositionId` | `Id` | ID of the critical `Inventory_Position__c` record (target) |
| `confirm` | `Boolean` | `false` = dry-run; `true` = execute |

**Returns:** `TransferResult` — with success flag + uhText

**Behavior:**
1. Loads target inventory position via `InventoryPositionSelector.getById()`. On failure, returns `success=false` with error message.
2. Checks DEA Schedule II compliance. If Schedule II, calls `logComplianceBlock()` and returns a hard stop with DEA Form 222 instructions.
3. Finds candidate source stores via `InventoryPositionSelector.findSurplusSources()`.
4. Filters candidates through `selectBestSource()` (cold-chain, DEA registration, expiry threshold).
5. If no eligible source found, returns a distributor fallback recommendation.
6. Calculates transfer quantity via `calculateTransferQty()`.
7. If `confirm = false`, calls `buildRecommendation()` — writes recommendation fields and returns uhText with "Shall I proceed?"
8. If `confirm = true`, calls `executeTransfer()` — atomic DML with savepoint, Transfer_Log__c, and rollback on failure.

**Throws:** Does not throw — all exceptions are caught and returned as `TransferResult(false, errorMessage)`.

### Private Methods

#### `isScheduleII(Inventory_Position__c inv)`

Returns `true` if the medication's DEA Schedule is `'II'`.

#### `selectBestSource(Inventory_Position__c target, List<Inventory_Position__c> candidates)`

Selects the best eligible source from the candidate list. Eligibility rules (all must pass): cold-chain capable if medication requires it, DEA registration on file, stock does not expire within 30 days. Candidates are pre-sorted by `Quantity__c DESC`, so the first eligible candidate is the best. Returns `null` if no candidate is eligible.

#### `calculateTransferQty(Inventory_Position__c target, Inventory_Position__c source)`

Calculates units to transfer: 50% of source surplus above safety stock, capped at target need to reach safety stock.

#### `buildRecommendation(Inventory_Position__c target, Inventory_Position__c source, Integer qty)`

Builds the dry-run recommendation. Writes full text to `Recommendation__c` (Long Text Area) and truncated text to `Recommendation_Preview__c` (Text 255). Checks CRUD/FLS before update. Returns `TransferResult` with "Shall I proceed?" prompt.

#### `executeTransfer(Inventory_Position__c target, Inventory_Position__c source, Integer qty)`

Executes the confirmed transfer atomically. Sets `Database.setSavepoint()`, checks CRUD permissions, deducts from source, adds to target, writes completion status to `Recommendation_Preview__c`, applies `Security.stripInaccessible()`, inserts `Transfer_Log__c` with `Transfer_Status__c = 'Completed'`. On any exception, calls `Database.rollback()` and returns error result.

#### `logComplianceBlock(Inventory_Position__c inv)`

Writes a `Transfer_Log__c` with `Transfer_Status__c = 'Blocked'` and `Quantity_Transferred__c = 0` when a Schedule II compliance stop is triggered. Fails silently if `Transfer_Log__c` is not creatable (does not fail the compliance stop itself).

---

## InventoryPositionSelector

**Selector for Inventory_Position__c — ALL SOQL for inventory queries. No DML. No business logic. Only reads.**

**Author:** IST Team  
**Since:** API v65.0  
**Sharing:** `with sharing`

### Public Methods

#### `getById(Id inventoryPositionId)`

**Fetch a single inventory position with full context for transfer evaluation.**

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `inventoryPositionId` | `Id` | Salesforce ID of the Inventory Position record |

**Returns:** `Inventory_Position__c` — with the following related fields loaded: `Store__r.Name`, `Store__r.Latitude__c`, `Store__r.Longitude__c`, `Store__r.Cold_Chain_Capable__c`, `Store__r.DEA_Registration__c`, `Store__r.Is_Active__c`, `Medication__r.Name`, `Medication__r.DEA_Schedule__c`, `Medication__r.Cold_Chain_Required__c`, `Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Status__c`, `Recommendation__c`

**Throws:**
- `IllegalArgumentException` — if `inventoryPositionId` is null
- `QueryException` — if no record is found

**Query Mode:** `WITH USER_MODE`

#### `findSurplusSources(Id medicationId, Id excludeStoreId, Integer minimumSurplus)`

**Find candidate source stores that hold surplus of a given medication.**

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `medicationId` | `Id` | ID of the medication to search for |
| `excludeStoreId` | `Id` | ID of the target store to exclude from results |
| `minimumSurplus` | `Integer` | Minimum `Quantity__c` threshold (defaults to 1 if null) |

**Returns:** `List<Inventory_Position__c>` — Candidate source positions, ordered by `Quantity__c DESC`. Same related fields loaded as `getById()`.

**Query Mode:** `WITH USER_MODE`

**Filters:**
- `Medication__c = :medicationId`
- `Store__c != :excludeStoreId`
- `Quantity__c > :minQty`
- `Store__r.Is_Active__c = true`

---

## ISTTestDataFactory

**Shared test data factory for all IST test classes.**

**Annotation:** `@IsTest`

### Public Methods

#### `createStore(String name, Boolean coldChain, String deaReg, Boolean active)`

Creates and inserts a `Pharmacy_Store__c` record. Sets `District__c = 'District 1'`, `Latitude__c = 37.7749`, `Longitude__c = -122.4194`.

**Returns:** `Pharmacy_Store__c` — the inserted record

#### `createMedication(String name, String deaSchedule, Boolean coldChain)`

Creates and inserts a `Medication__c` record. Generates `NDC__c` as `'NDC-' + name (spaces replaced with dashes) + '-001'`.

**Returns:** `Medication__c` — the inserted record

#### `createInventory(Id storeId, Id medId, Integer qty, Integer safetyStock, Integer daysToExpiry)`

Creates and inserts an `Inventory_Position__c` record. Sets `Expiry_Date__c = Date.today().addDays(daysToExpiry)`.

**Returns:** `Inventory_Position__c` — the inserted record
