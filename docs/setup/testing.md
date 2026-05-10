---
layout: default
title: Testing
parent: Setup
nav_order: 2
---

# Testing Guide

> **Current state:** the repository ships `ISTTestDataFactory.cls` (an `@IsTest` data builder) but **no test class consumes it**. Coverage on `InterStoreTransferService`, `InterStoreTransferAction`, and `InventoryPositionSelector` is therefore **0%**, which means a production deploy with `RunLocalTests` will fail. This page documents what's there, what's missing, and the test scenarios that need to be authored before a production release.

---

## What's in the repo

`ISTTestDataFactory` is a `@IsTest`-annotated public class with three static helpers:

```apex
public static Pharmacy_Store__c createStore(
    String name, Boolean coldChain, String deaReg, Boolean active
);

public static Medication__c createMedication(
    String name, String deaSchedule, Boolean coldChain
);

public static Inventory_Position__c createInventory(
    Id storeId, Id medId, Integer qty, Integer safetyStock, Integer daysToExpiry
);
```

Each helper inserts a single record with sensible defaults (San Francisco lat/lng on stores, auto-generated NDC on medications, today + N days expiry on inventory) and returns it. They're designed to be composable inside `Test.startTest()` blocks.

---

## What's missing

A test class — call it `InterStoreTransferServiceTest` — that exercises every code path in `InterStoreTransferService.evaluate()`. The test scenarios below correspond directly to the demo `TC*` scripts in `scripts/apex/`, so the assertions and setup data should be familiar.

### Recommended test methods

| Test method | Setup | Assertions |
|---|---|---|
| `evaluate_happyPathDryRun_writesRecommendation` | Two cold-chain stores with `DEA_Registration__c`; one cold-chain medication; target qty 0 / safety 50; source qty 200 / safety 50 / expiry +90d | `result.success == true`; `result.recommendedQty == 50`; target's `Recommendation__c` and `Recommendation_Preview__c` are populated; no `Transfer_Log__c` written |
| `evaluate_happyPathExecute_atomicallyTransfers` | Same as above, then call with `confirm=true` | Source quantity decremented by 50; target quantity incremented by 50; one `Transfer_Log__c` with status `Completed` and matching `Quantity_Transferred__c` |
| `evaluate_scheduleII_blocksWithoutSourceSearch` | Schedule II medication; target store with low qty; multiple candidate sources with surplus | `result.success == false`; `uhText` contains `"Schedule II"` and `"DEA Form 222"`; one `Transfer_Log__c` with status `Blocked`, `Source_Store__c == null`, `Quantity_Transferred__c == 0` |
| `evaluate_noEligibleSources_returnsDistributorFallback` | Cold-chain medication; only candidate is non-cold-chain capable | `result.success == false`; `uhText` contains `"No suitable source"` and `"emergency order"` |
| `evaluate_nearExpirySource_excluded` | Single candidate with `Expiry_Date__c = today + 15` | `selectBestSource` returns null → distributor fallback |
| `evaluate_blankDeaRegistration_excluded` | Single candidate with `DEA_Registration__c = ''` | Distributor fallback |
| `evaluate_inactiveStore_excluded` | Single candidate at `Is_Active__c = false` store | Selector SOQL filter excludes it; distributor fallback |
| `evaluate_qtyCappedAtTargetNeed` | Source surplus 200, target need 30 | `recommendedQty == 30` (not `200 × 50% = 100`) |
| `evaluate_qtyCappedAtSourceHalfSurplus` | Source surplus 60, target need 100 | `recommendedQty == 30` (50% of source surplus, not target's full need) |
| `evaluate_invalidId_returnsGracefulError` | Pass a deleted or non-existent Id | `result.success == false`; `uhText` starts with `"Unable to locate Inventory Position"` |
| `executeTransfer_dmlException_rollsBack` | Inject a `DmlException` (e.g. by patching the source record to violate a validation rule before `update`) | `result.success == false`; `uhText` contains `"fully rolled back"`; source/target quantities unchanged |

### Suggested coverage targets

| Class | Target |
|---|---|
| `InterStoreTransferService` | ≥90% (this is where the policy lives) |
| `InterStoreTransferAction` | ≥85% (just a wrapper, but invocable methods need coverage too) |
| `InventoryPositionSelector` | ≥85% (covered indirectly by service tests; add a direct selector test for `getById` exception paths) |
| `PostInstallScript` | Optional — `InstallHandler.onInstall` is hard to unit-test cleanly. Consider extracting the data-creation logic into a `static` helper that a test can call directly |

---

## Running tests

Once a test class exists:

```bash
# Run a single class
sf apex run test --class-names InterStoreTransferServiceTest --target-org ist-dev --result-format human --code-coverage

# Run all local tests with coverage
sf apex run test --target-org ist-dev --code-coverage --result-format human --wait 10

# Get coverage breakdown for a specific class
sf apex get test --test-run-id <run-id> --code-coverage --target-org ist-dev --output-dir test-results
```

`--wait 10` blocks the CLI until the test run completes (10-minute timeout). Without `--wait`, the command returns immediately and prints a job ID you can poll with `sf apex get test`.

---

## Test data strategy

Use `ISTTestDataFactory` for all setup. The factory's defaults are deliberately permissive (cold-chain stores, fresh expiry dates) so that tests opt in to constraint scenarios:

```apex
@IsTest
private class InterStoreTransferServiceTest {

    @IsTest
    static void evaluate_happyPathDryRun_writesRecommendation() {
        // ARRANGE
        Pharmacy_Store__c target = ISTTestDataFactory.createStore(
            'Target Store', /* coldChain */ true, /* deaReg */ 'DEA-T-001', /* active */ true
        );
        Pharmacy_Store__c source = ISTTestDataFactory.createStore(
            'Source Store', /* coldChain */ true, /* deaReg */ 'DEA-S-001', /* active */ true
        );
        Medication__c med = ISTTestDataFactory.createMedication(
            'Mounjaro 5mg', /* deaSchedule */ 'None', /* coldChain */ true
        );
        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            target.Id, med.Id, /* qty */ 0, /* safety */ 50, /* daysToExpiry */ 120
        );
        ISTTestDataFactory.createInventory(
            source.Id, med.Id, /* qty */ 200, /* safety */ 50, /* daysToExpiry */ 90
        );

        // ACT
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, /* confirm */ false);
        Test.stopTest();

        // ASSERT
        System.assertEquals(true, result.success, 'Expected dry-run success');
        System.assertEquals(50, result.recommendedQty, 'Expected qty capped at target need');
        Inventory_Position__c reloaded =
            [SELECT Recommendation__c, Recommendation_Preview__c
             FROM Inventory_Position__c WHERE Id = :targetInv.Id];
        System.assertNotEquals(null, reloaded.Recommendation__c);
        System.assert(reloaded.Recommendation_Preview__c.length() <= 255);
        System.assertEquals(0,
            [SELECT COUNT() FROM Transfer_Log__c WHERE Inventory_Position__c = :targetInv.Id],
            'Dry-run should not write a Transfer_Log__c');
    }

    // ... 10 more tests
}
```

---

## Async testing notes

This project does **not** use `Queueable`, `Batch`, `Future`, or `@Schedulable`, so test classes don't need `Test.startTest()`/`Test.stopTest()` to drain async queues. The pair is still useful as a governor-limit reset boundary (one set of limits before, another after), and is included in the example above as the standard pattern.

The Flow `Execute_Inter_Store_Transfer` is auto-launched and synchronous; it can be tested by invoking `InterStoreTransferAction.execute()` directly with a list of `ActionInput` rather than through the Flow runtime.

---

## CI considerations

Once a test class exists, a minimal CI workflow looks like:

```yaml
- name: Validate against sandbox
  run: |
    sf project deploy validate \
      --source-dir force-app \
      --target-org ${{ secrets.SANDBOX_ALIAS }} \
      --test-level RunLocalTests \
      --code-coverage-required 75
```

This runs the full test suite as a check-only deploy and fails the workflow if coverage drops below 75%. Run it on every PR; gate merges on success.
