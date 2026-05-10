---
layout: default
title: Apex Classes
parent: API Reference
nav_order: 1
---

# Apex Classes Reference

ApexDox-style reference for every class in `force-app/main/default/classes/`.

| Class | Sharing | Purpose |
|---|---|---|
| [`InterStoreTransferService`](#interstoretransferservice) | `with sharing` | Core service. All compliance, eligibility, and DML logic |
| [`InterStoreTransferAction`](#interstoretransferaction) | `with sharing` | `@InvocableMethod` wrapper for Flow / Agentforce |
| [`InventoryPositionSelector`](#inventorypositionselector) | `with sharing` | All SOQL queries; no DML, no business logic |
| [`PostInstallScript`](#postinstallscript) | (none declared) | `InstallHandler` for post-package-install setup |
| [`ISTTestDataFactory`](#isttestdatafactory) | `@IsTest` | Test data builder helpers (no test class consumes it yet) |

---

## `InterStoreTransferService`

`public with sharing class InterStoreTransferService`

Core service for Inter-Store Transfer operations. Enforces DEA Schedule II compliance, cold-chain matching, inventory locking, and atomic DML with audit trail.

**Author:** IST Team. **Since:** API v65.0.

**Contract:**

- `confirm = false` → dry-run, returns recommendation only; writes `Recommendation__c` + `Recommendation_Preview__c`.
- `confirm = true` → executes transfer atomically with `Transfer_Log__c`.

### Constants

| Name | Value | Purpose |
|---|---|---|
| `TRANSFER_BUFFER_PCT` | `50` | Transfer 50% of source surplus above its safety stock |
| `MIN_DAYS_TO_EXPIRY` | `30` | Source stock expiring within this many days is excluded |
| `DEA_SCHEDULE_II` | `'II'` | DEA Schedule that triggers a hard compliance block |
| `PREVIEW_MAX_LENGTH` | `255` | Max length of Text(255) `Recommendation_Preview__c` Grid column |

### Inner class: `TransferResult`

```apex
public class TransferResult {
    public Boolean success;
    public String  uhText;
    public Id      sourceStoreId;
    public String  sourceStoreName;
    public Integer recommendedQty;
    public Id      transferLogId;

    public TransferResult(Boolean success, String uhText) { ... }
}
```

Structured result returned to `InterStoreTransferAction`. `success = false` always includes a next action in `uhText` — never a dead end.

| Field | Type | Notes |
|---|---|---|
| `success` | `Boolean` | `true` for successful recommendation or execution; `false` for compliance block, no source, or rollback |
| `uhText` | `String` | Full human-readable text the agent surfaces in the Grid conversation |
| `sourceStoreId` | `Id` | Set when a source is identified (dry-run or execute paths) |
| `sourceStoreName` | `String` | Set when a source is identified |
| `recommendedQty` | `Integer` | Set when a source is identified |
| `transferLogId` | `Id` | Only set on successful execution; null on dry-run or any failure |

### `evaluate(Id inventoryPositionId, Boolean confirm) : TransferResult`

```apex
public static TransferResult evaluate(Id inventoryPositionId, Boolean confirm)
```

Evaluate and optionally execute an inter-store transfer.

**Parameters**

- `inventoryPositionId` — Id of the critical `Inventory_Position__c` record (the *target* of the transfer).
- `confirm` — `false` = dry-run, `true` = execute.

**Returns** `TransferResult` with success flag and `uhText`.

**Behaviour summary**

1. Loads target position via `InventoryPositionSelector.getById()`. On `Exception`, returns a graceful "Unable to locate Inventory Position" result.
2. Checks `isScheduleII(target)`. On hit: writes a `Blocked` `Transfer_Log__c` and returns the DEA Form 222 message.
3. Calls `InventoryPositionSelector.findSurplusSources(medicationId, excludeStoreId, target.Safety_Stock__c + 1)`.
4. Calls `selectBestSource(target, candidates)` to apply eligibility filters.
5. If no eligible source → returns the distributor-fallback `uhText`.
6. Calls `calculateTransferQty(target, bestSource)`.
7. If `!confirm` → calls `buildRecommendation(...)` and returns.
8. If `confirm` → calls `executeTransfer(...)` and returns.

### Private helpers

| Method | Returns | Purpose |
|---|---|---|
| `isScheduleII(Inventory_Position__c)` | `Boolean` | True when `Medication__r.DEA_Schedule__c == 'II'` |
| `selectBestSource(target, candidates)` | `Inventory_Position__c` | First candidate passing cold-chain + DEA registration + ≥30-day expiry checks |
| `calculateTransferQty(target, source)` | `Integer` | `min( (sourceQty - sourceSafety) × 50 / 100 , targetSafety - targetQty )` |
| `buildRecommendation(target, source, qty)` | `TransferResult` | Writes `Recommendation__c` + `Recommendation_Preview__c`; returns `success=true` with full `uhText` ending in *"Shall I proceed with this transfer?"* |
| `executeTransfer(target, source, qty)` | `TransferResult` | Atomic DML inside `Database.setSavepoint()`; updates source/target quantities, inserts `Completed` `Transfer_Log__c`, rolls back on any exception |
| `logComplianceBlock(inv)` | `void` | Inserts a `Blocked` `Transfer_Log__c` for Schedule II requests; swallows insert failure with a `LoggingLevel.WARN` debug to avoid blocking the compliance stop itself |

---

## `InterStoreTransferAction`

`public with sharing class InterStoreTransferAction`

Agentforce Invocable Action: Execute Inter-Store Transfer. The Grid's Transfer/Optimize button triggers this action via the `Execute_Inter_Store_Transfer` Flow. The agent calls it twice per workflow:

- 1st call: `confirm = false` → recommendation + *"Shall I proceed?"*
- 2nd call: `confirm = true` → atomic execution

**Author:** IST Team. **Since:** API v65.0.

### Inner class: `ActionInput`

| Variable | Type | `@InvocableVariable` attributes | Notes |
|---|---|---|---|
| `inventoryPositionId` | `Id` | label `Inventory Position ID`, required `true` | The Salesforce ID of the critical `Inventory_Position__c` record |
| `confirm` | `Boolean` | label `Confirm Transfer`, required `false`, defaultValue `'true'` | `false` = dry-run, `true` = execute |

> Note: the `defaultValue = 'true'` on `confirm` is the *Flow input default* shown in the builder. The runtime code in `execute()` defaults to `false` when `input.confirm` is null: `Boolean confirmFlag = input.confirm != null ? input.confirm : false;`. The Flow default and the Apex null-coalesce default disagree — in practice the Flow always passes a non-null value, so this discrepancy doesn't surface, but it's worth knowing if you call the action from Apex directly.

### Inner class: `ActionOutput`

| Variable | Type | `@InvocableVariable` label |
|---|---|---|
| `success` | `Boolean` | `Success` |
| `uhText` | `String` | `UH Text` |
| `sourceStoreId` | `Id` | `Source Store ID` |
| `sourceStoreName` | `String` | `Source Store Name` |
| `recommendedQty` | `Integer` | `Recommended Quantity` |
| `transferLogId` | `Id` | `Transfer Log ID` |

### `execute(List<ActionInput>) : List<ActionOutput>`

```apex
@InvocableMethod(
    label       = 'Execute Inter-Store Transfer'
    description = 'Recommends (dry-run) or executes an inter-store inventory transfer for a critical stock row. Schedule II drugs are automatically blocked. Returns uhText for agent to surface.'
    category    = 'Inventory Management'
    callout     = false
)
public static List<ActionOutput> execute(List<ActionInput> inputs)
```

For each input, calls `InterStoreTransferService.evaluate(inputId, confirmFlag)` and copies fields from the `TransferResult` into a new `ActionOutput`.

Agentforce always passes a list of one for single-row Grid actions, but the method is bulk-safe in shape. Note that the **service is not bulkified** — each iteration runs its own SOQL queries — so calling this action with a large input list will hit governor limits.

---

## `InventoryPositionSelector`

`public with sharing class InventoryPositionSelector`

Selector for `Inventory_Position__c`. All SOQL for inventory queries lives here. No DML, no business logic, only reads.

**Author:** IST Team. **Since:** API v65.0.

### `getById(Id inventoryPositionId) : Inventory_Position__c`

```apex
public static Inventory_Position__c getById(Id inventoryPositionId)
```

Fetches a single inventory position with full relational context for transfer evaluation. Throws `IllegalArgumentException` if the id is null, `QueryException` if the row is not found.

The selected fields cover everything `evaluate()` needs without a second hop:

- Core: `Id`, `Name`, `Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Status__c`, `Recommendation__c`
- `Store__r`: `Name`, `Latitude__c`, `Longitude__c`, `Cold_Chain_Capable__c`, `DEA_Registration__c`, `Is_Active__c`
- `Medication__r`: `Name`, `DEA_Schedule__c`, `Cold_Chain_Required__c`

Query uses `WITH SECURITY_ENFORCED`.

### `findSurplusSources(Id medicationId, Id excludeStoreId, Integer minimumSurplus) : List<Inventory_Position__c>`

```apex
public static List<Inventory_Position__c> findSurplusSources(
    Id medicationId,
    Id excludeStoreId,
    Integer minimumSurplus
)
```

Finds candidate source stores holding surplus of a given medication. Excludes the target store. Orders by `Quantity__c DESC` (most surplus first), so the first candidate that passes eligibility filters in `selectBestSource()` is the highest-stock eligible source.

`minimumSurplus` defaults to 1 if null. Same field set as `getById()` minus `Recommendation__c` (sources don't need it). Uses `WITH SECURITY_ENFORCED` and filters `Store__r.Is_Active__c = true`.

---

## `PostInstallScript`

`public class PostInstallScript implements InstallHandler`

Executes automatically after package installation. Does **not** declare `with sharing` — `InstallHandler` runs in system context anyway.

### `onInstall(InstallContext context) : void`

Five steps, wrapped in a top-level `try / catch` that swallows exceptions to avoid blocking the package install. Failures are logged at `LoggingLevel.ERROR`.

1. **`createPharmacyStores()`** — inserts 6 `Pharmacy_Store__c` records across two districts:
   - District 1 (Bay Area): `CVS Downtown SF`, `CVS Westside SF`, `CVS Eastside Oakland`
   - District 2 (South Bay): `CVS San Jose Central`, `CVS Sunnyvale`, `CVS Palo Alto (Closed)` (`Is_Active__c = false`)
   - `CVS Eastside Oakland` is *not* cold-chain capable; the rest are.
   - `CVS Sunnyvale` has an empty `DEA_Registration__c` to demonstrate the eligibility filter.
2. **`createMedications()`** — inserts 6 `Medication__c` records: `Mounjaro 5mg`, `Ozempic 1mg` (cold-chain), `Adderall XR 30mg` (Schedule II), `Xanax 0.5mg` (Schedule IV), `Lisinopril 10mg`, `Amoxicillin 500mg`.
3. **`createInventoryPositions()`** — inserts 14 `Inventory_Position__c` records covering 6 demo scenarios (happy path, Schedule II block, distributor fallback, near-expiry exclusion, Schedule IV allowed, multiple healthy sources).
4. **`assignPermissionSet(Id userId)`** — assigns `IST_Ops_User` to the installer; idempotent (skips if already assigned).
5. **`verifyPromptTemplate()`** — uses `Database.query` to verify `IST_Inventory_Recommendation` exists in `AiPrompt`. Logs at `LoggingLevel.INFO` if Agentforce is not enabled in the org.

---

## `ISTTestDataFactory`

`@IsTest public class ISTTestDataFactory`

Shared test data factory for IST test classes. Three static helpers:

| Method | Inserts | Notes |
|---|---|---|
| `createStore(String name, Boolean coldChain, String deaReg, Boolean active)` | `Pharmacy_Store__c` | Fixed `District__c = 'District 1'`; lat/lng pinned to San Francisco (37.7749, -122.4194) |
| `createMedication(String name, String deaSchedule, Boolean coldChain)` | `Medication__c` | NDC auto-generated as `NDC-<name with spaces dashed>-001` |
| `createInventory(Id storeId, Id medId, Integer qty, Integer safetyStock, Integer daysToExpiry)` | `Inventory_Position__c` | `Expiry_Date__c = Date.today().addDays(daysToExpiry)`; `Recommendation__c = ''` |

> **Heads up:** as of this release there is **no test class** that consumes the factory. To deploy to a production org you need ≥75% Apex coverage — see [Testing Guide](../setup/testing.html) for the test scenarios that need to be authored.
