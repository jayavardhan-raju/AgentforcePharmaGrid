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
| [`ISTTestDataFactory`](#isttestdatafactory) | `@IsTest` | Test data builder helpers shared by every test class |
| [`InterStoreTransferServiceTest`](#interstoretransferservicetest) | `@IsTest private` | 11 methods covering compliance, qty math, FLS, rollback |
| [`InterStoreTransferActionTest`](#interstoretransferactiontest) | `@IsTest private` | 7 methods covering dry-run, execute, default `confirm`, bulk input |
| [`InventoryPositionSelectorTest`](#inventorypositionselectortest) | `@IsTest private` | 10 methods covering `getById`, `findSurplusSources`, security_enforced |
| [`PostInstallScriptTest`](#postinstallscripttest) | `@IsTest private` | 11 methods covering install steps, permset assignment, prompt-template verification |

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
5. **`verifyPromptTemplate()`** — uses dynamic SOQL (`Database.query`) to check whether `IST_Inventory_Recommendation` exists as an `AiPrompt` row. Behavior:
   - **Found:** debugs `Name`, `DeveloperName`, `ActiveVersion`, and `Id` at default level.
   - **Not found:** debugs a `LoggingLevel.WARN` message instructing the admin to create the template manually per [Create the Prompt Template](../setup/create-prompt-template.html). The template is **not deployed by this package** — `GenAiPromptTemplate` metadata requires server-generated hash identifiers that cannot be authored by hand.
   - **Query throws:** debugs `LoggingLevel.INFO` ("expected if Agentforce is not enabled"); the install continues.

> The install handler intentionally swallows all exceptions in `onInstall`, so neither a missing prompt template nor a permission-set failure can block a package install. Admins should read the post-install debug log to confirm every step succeeded.

---

## `ISTTestDataFactory`

`@IsTest public class ISTTestDataFactory`

Shared test data factory consumed by every test class in this project. Three static helpers:

| Method | Inserts | Notes |
|---|---|---|
| `createStore(String name, Boolean coldChain, String deaReg, Boolean active)` | `Pharmacy_Store__c` | Fixed `District__c = 'District 1'`; lat/lng pinned to San Francisco (37.7749, -122.4194) |
| `createMedication(String name, String deaSchedule, Boolean coldChain)` | `Medication__c` | NDC auto-generated as `NDC-<name with spaces dashed>-001` |
| `createInventory(Id storeId, Id medId, Integer qty, Integer safetyStock, Integer daysToExpiry)` | `Inventory_Position__c` | `Expiry_Date__c = Date.today().addDays(daysToExpiry)`; `Recommendation__c = ''` |

---

## `InterStoreTransferServiceTest`

`@IsTest private class InterStoreTransferServiceTest`

Comprehensive coverage of `InterStoreTransferService.evaluate()` — every code path, every eligibility filter, every error branch. Uses `@TestSetup` to materialise five stores (good, no-cold-chain, no-DEA, inactive) and four medications (Schedule II, cold-chain, Schedule IV, standard).

| Test method | Asserts |
|---|---|
| `testScheduleIIComplianceBlock` | `result.success == false`; `uhText` contains the Schedule II / DEA Form 222 message; a `Blocked` `Transfer_Log__c` is written |
| `testSuccessfulDryRun` | `result.success == true`; `recommendedQty` matches the qty-math formula; `Recommendation__c` and `Recommendation_Preview__c` are populated; **no** `Transfer_Log__c` written |
| `testSuccessfulExecution` | Source quantity decremented, target quantity incremented, `Completed` `Transfer_Log__c` written with full `Notes__c` |
| `testColdChainFiltering` | Cold-chain medication with only non-cold-chain source → distributor-fallback `uhText` |
| `testDEARegistrationFiltering` | Source with blank `DEA_Registration__c` → distributor fallback |
| `testExpiryDateFiltering` | Source with `Expiry_Date__c < today + 30` → distributor fallback |
| `testQuantityCalculation` | Validates `min(sourceSurplus × 50%, targetNeed)` cap |
| `testInvalidInventoryPositionId` | Bad id returns `success = false` with graceful `uhText` |
| `testBestSourceSelection` | Multiple candidates → highest-quantity eligible one wins (pre-sorted by `Quantity__c DESC`) |
| `testPreviewTextTruncation` | Long `uhText` truncated to `PREVIEW_MAX_LENGTH − 3` and suffixed with `...` |
| `testNoSuitableSource` (in action suite) | Empty candidate list → distributor fallback |

---

## `InterStoreTransferActionTest`

`@IsTest private class InterStoreTransferActionTest`

Covers the `@InvocableMethod` wrapper. Validates that `confirm` defaulting, multi-input bulk shape, and result mapping all behave correctly.

| Test method | Asserts |
|---|---|
| `testDryRunAction` | `confirm = false` returns `success = true`, `uhText` ending in *"Shall I proceed?"*, populated `sourceStoreId` / `sourceStoreName` / `recommendedQty` |
| `testExecutionAction` | `confirm = true` returns a populated `transferLogId` |
| `testDefaultConfirmValue` | When `input.confirm` is `null`, the action falls back to `false` (dry-run) per the null-coalesce in `execute()` |
| `testScheduleIIThroughAction` | Schedule II input → `success = false`; `uhText` matches the service's compliance message |
| `testMultipleInputs` | List of two `ActionInput`s returns two `ActionOutput`s in the same order |
| `testInvalidIdThroughAction` | Bad id surfaces through the action with `success = false` and a graceful `uhText` |
| `testNoSuitableSourceThroughAction` | Distributor fallback surfaces through the action |

---

## `InventoryPositionSelectorTest`

`@IsTest private class InventoryPositionSelectorTest`

Direct unit tests on the selector. Covers exception paths the service tests cannot reach indirectly.

| Test method | Asserts |
|---|---|
| `testGetByIdSuccess` | Returns a fully hydrated row with all `Store__r.*` and `Medication__r.*` fields |
| `testGetByIdNullId` | Throws `IllegalArgumentException` for a null id |
| `testGetByIdNonExistent` | Throws `QueryException` for a non-existent id |
| `testFindSurplusSourcesMultiple` | Returns multiple candidates ordered by `Quantity__c DESC` |
| `testFindSurplusSourcesNone` | Returns empty list when no surplus exists |
| `testFindSurplusSourcesInactiveExcluded` | Filters out `Is_Active__c = false` stores |
| `testFindSurplusSourcesMinimumFilter` | Honors the `minimumSurplus` argument |
| `testFindSurplusSourcesNullMinimum` | Defaults `minimumSurplus` to 1 when null |
| `testFindSurplusSourcesAllFields` | All selected fields are present on the returned rows |
| `testSecurityEnforced` | `WITH SECURITY_ENFORCED` is honored under a restricted user context |

---

## `PostInstallScriptTest`

`@IsTest private class PostInstallScriptTest`

Exercises every step of the `InstallHandler`. Because `onInstall` is hard to invoke directly, several tests refactor the verification logic by invoking the public install handler with a stubbed `InstallContext`.

| Test method | Asserts |
|---|---|
| `testSuccessfulPostInstall` | All six stores, six medications, and 14 inventory positions are created end-to-end |
| `testStoreCreation` | Validates districts, lat/lng, cold-chain flags, DEA registrations, and `CVS Palo Alto (Closed)` is inactive |
| `testMedicationCreation` | Validates schedules, NDCs, and cold-chain flags for all six demo medications |
| `testInventoryPositionCreation` | Validates the six scenario buckets (happy path, Schedule II, fallback, near-expiry, Schedule IV, multi-healthy) |
| `testPermissionSetAssignment` | New assignment created for the install user |
| `testDuplicatePermissionSetAssignment` | Idempotent on re-run; no duplicate assignment |
| `testVersionLogging` | The `context.previousVersion()` value is logged |
| `testPromptTemplateVerification` | `verifyPromptTemplate()` runs without throwing whether or not the template exists |
| `testErrorHandling` | Failures inside `onInstall` are caught and logged at `LoggingLevel.ERROR` so the install never bubbles an exception to the platform |
| `testAllInventoryScenarios` | Asserts each demo scenario's quantity / safety-stock / expiry pattern |

---

## Running the test suite

```bash
sf apex run test \
  --class-names InterStoreTransferServiceTest,InterStoreTransferActionTest,InventoryPositionSelectorTest,PostInstallScriptTest \
  --target-org your-org \
  --result-format human \
  --code-coverage \
  --wait 10
```

For production-deploy validation, use `--test-level RunLocalTests` on a `sf project deploy validate` command — every test method in the four classes will run, and combined coverage exceeds the 75% production gate. See [Testing Guide](../setup/testing.html) for coverage targets per class and CI examples.
