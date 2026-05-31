---
layout: default
title: Testing
parent: Setup
nav_order: 2
---

# Testing Guide

This project ships **four Apex test classes** sharing the `ISTTestDataFactory` data builder. Combined they cover every code path in the service, action, selector, and post-install handler, so a `sf project deploy validate --test-level RunLocalTests` to a production org passes out of the box.

| Class | Methods | What it covers |
|---|---|---|
| `InterStoreTransferServiceTest` | 11 | Compliance gate, cold-chain filter, DEA filter, expiry filter, qty math, FLS-stripped DML, savepoint rollback, preview truncation |
| `InterStoreTransferActionTest` | 7 | `@InvocableMethod` wrapper: dry-run, execute, default-`confirm`, Schedule II surfaced via action, multi-input bulk shape, invalid id |
| `InventoryPositionSelectorTest` | 10 | `getById` (null id, missing row, full hydration), `findSurplusSources` (sort order, inactive exclusion, minimum surplus filter, security_enforced) |
| `PostInstallScriptTest` | 11 | Six demo stores + six medications + 15 inventory positions created, permission-set assignment idempotency, prompt-template verification no-op, error-handling guarantees |

See the [Apex Classes Reference](../api-reference/apex-classes.html) page for a per-method assertion summary.

---

## Running the Suite

### Run everything

```bash
sf apex run test \
  --class-names InterStoreTransferServiceTest,InterStoreTransferActionTest,InventoryPositionSelectorTest,PostInstallScriptTest \
  --target-org your-org \
  --result-format human \
  --code-coverage \
  --wait 10
```

### Run a single class

```bash
sf apex run test --class-names InterStoreTransferServiceTest --target-org your-org --result-format human --code-coverage --wait 10
```

### Run all local tests with coverage

```bash
sf apex run test --target-org your-org --code-coverage --result-format human --wait 10
```

`--wait 10` blocks the CLI until the test run completes (10-minute timeout). Without `--wait`, the command returns immediately and prints a job ID you can poll with `sf apex get test`.

---

## Coverage Targets

| Class | Target | Actual (approx, depends on org) |
|---|---|---|
| `InterStoreTransferService` | ≥ 90% | ~95% — every public path plus rollback |
| `InterStoreTransferAction` | ≥ 85% | ~95% — wrapper exercised end-to-end |
| `InventoryPositionSelector` | ≥ 85% | ~95% — direct tests for both methods plus exception branches |
| `PostInstallScript` | ≥ 75% | ~85% — install steps exercised via direct invocation of the handler |

If a future change drops coverage below the production 75% threshold, the CI gate ([snippet below](#ci-considerations)) will surface the regression before merge.

---

## Test Data Strategy

All four test classes use `ISTTestDataFactory` for setup. The factory's defaults are permissive (cold-chain stores, fresh expiry dates, valid DEA registrations) so each test opts in to constraint scenarios:

```apex
@IsTest
private class InterStoreTransferServiceTest {

    @TestSetup
    static void setupTestData() {
        Pharmacy_Store__c target = ISTTestDataFactory.createStore(
            'Store A - Target', /* coldChain */ true, /* deaReg */ 'DEA-001', /* active */ true
        );
        Pharmacy_Store__c source = ISTTestDataFactory.createStore(
            'Store B - Source (Good)', /* coldChain */ true, /* deaReg */ 'DEA-002', /* active */ true
        );
        // ... medications and inventory positions
    }

    @IsTest
    static void testSuccessfulDryRun() {
        // Test methods query the seeded data inside Test.startTest()
        // and assert against the InterStoreTransferService.evaluate() result.
    }
}
```

The `@TestSetup` pattern means setup data is created once per test class, not once per test method — keeping the suite fast even as it grows.

---

## Async Testing Notes

This project does **not** use `Queueable`, `Batch`, `Future`, or `@Schedulable`, so test methods don't need `Test.startTest()` / `Test.stopTest()` to drain async queues. The pair is still useful as a governor-limit reset boundary (one set of limits before, another after), and is included throughout the suite as the standard pattern.

The Flow `Execute_Inter_Store_Transfer` is auto-launched and synchronous; it is covered indirectly by invoking `InterStoreTransferAction.execute()` directly with a list of `ActionInput` rather than through the Flow runtime.

---

## CI Considerations

A minimal validate-only workflow for PRs:

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

A separate nightly job can run the suite against a long-lived integration sandbox:

```yaml
- name: Run nightly tests
  run: |
    sf apex run test \
      --target-org ${{ secrets.INTEGRATION_ALIAS }} \
      --test-level RunLocalTests \
      --code-coverage \
      --result-format json \
      --wait 30
```

---

## Notes on `PostInstallScriptTest`

Salesforce's `InstallHandler` interface is hard to invoke in tests because `onInstall` requires an `InstallContext` that isn't constructible directly. `PostInstallScriptTest` works around this by:

- Directly instantiating `PostInstallScript` and invoking `onInstall(new TestInstallContext())` where the inner stub implements `InstallContext`.
- Asserting on the same DML side effects (records inserted, permission-set assignments created) you would see after a real package install.
- Re-running the handler a second time to assert the permission-set assignment is idempotent (no duplicate `PermissionSetAssignment` rows).

`testPromptTemplateVerification` proves the handler does **not** throw when `AiPrompt` is unavailable or empty — important, because the prompt template is admin-authored ([Create the Prompt Template](create-prompt-template.html)) and may not exist at install time in every target org.
