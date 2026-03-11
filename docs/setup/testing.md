---
layout: default
title: Testing Guide
parent: Setup
nav_order: 2
---

# Testing Guide

AgentforceGrid includes comprehensive test classes following Salesforce testing best practices with a shared test data factory pattern.

---

## Running Tests

### Run All Local Tests

```bash
sf apex run test \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --target-org <your-org-alias>
```

### Run a Specific Test Class

```bash
sf apex run test \
  --class-names InterStoreTransferServiceTest \
  --code-coverage \
  --result-format human \
  --target-org <your-org-alias>
```

### Run All IST Tests

```bash
sf apex run test \
  --class-names InterStoreTransferServiceTest InterStoreTransferActionTest \
  --code-coverage \
  --result-format human \
  --target-org <your-org-alias>
```

---

## Test Classes

### InterStoreTransferServiceTest

Tests the core service layer business logic. 8 test methods.

| Test Method | Scenario | Asserts |
|-------------|----------|---------|
| `testEvaluate_HappyPath_DryRun_ReturnsRecommendation` | Dry-run with eligible source store | `success=true`, uhText contains "Shall I proceed" and source store name, `recommendedQty > 0`, `transferLogId = null` |
| `testEvaluate_HappyPath_Execute_CreatesTransferLog` | Confirmed execution | `success=true`, `Transfer_Log__c` created with `Completed` status, source inventory decreased, transfer log quantity > 0 |
| `testEvaluate_ScheduleII_DryRun_HardStop` | Schedule II medication dry-run | `success=false`, uhText mentions "Schedule II" and "DEA Form 222", no confirmation prompt, `Transfer_Log__c` with `Blocked` status created |
| `testEvaluate_ScheduleII_ConfirmTrue_StillBlocked` | Schedule II with `confirm=true` | `success=false`, no `Completed` transfer logs exist — proves confirm cannot bypass compliance |
| `testEvaluate_NoSuitableSource_ReturnsFallback` | No source stores with surplus | `success=false`, uhText mentions "No suitable source store found" and "distributor", no confirmation prompt |
| `testEvaluate_NoSuitableSource_ColdChainMismatch` | Source exists but lacks cold-chain | `success=false` — cold-chain mismatch causes source to be filtered out |
| `testEvaluate_NullId_ReturnsErrorGracefully` | Null inventory position ID | `success=false`, non-blank uhText — graceful error handling |
| `testEvaluate_ExpiredSourceStock_Excluded` | Source stock expires in < 30 days | `success=false` — near-expiry source is excluded |

### InterStoreTransferActionTest

Tests the invocable action adapter layer. 3 test methods.

| Test Method | Scenario | Asserts |
|-------------|----------|---------|
| `testAction_HappyPath_DryRun_ReturnsOutput` | Dry-run through action layer | Output list size = 1, `success=true`, uhText and sourceStoreName not null, `recommendedQty > 0` |
| `testAction_ScheduleII_ReturnsComplianceBlock` | Schedule II through action layer | `success=false`, uhText contains "Schedule II" |
| `testAction_NullConfirm_DefaultsToFalse` | `confirm=null` input | No `Completed` transfer logs exist — proves null defaults to dry-run |

### ISTTestDataFactory

Shared test data factory. Not a test class itself — covered transitively through usage in the test classes above.

| Method | Creates |
|--------|---------|
| `createStore()` | `Pharmacy_Store__c` with District 1, SF coordinates (37.7749, -122.4194), configurable cold-chain, DEA reg, and active status |
| `createMedication()` | `Medication__c` with auto-generated NDC, configurable DEA schedule and cold-chain requirement |
| `createInventory()` | `Inventory_Position__c` linked to store and medication, with configurable quantity, safety stock, and days to expiry |

---

## Coverage Map

| Class Under Test | Covered By | Key Scenarios |
|------------------|-----------|---------------|
| `InterStoreTransferService` | `InterStoreTransferServiceTest` | Happy path (dry-run + execute), Schedule II (dry-run + confirm=true), no source fallback, cold-chain mismatch, null ID, expired source |
| `InterStoreTransferAction` | `InterStoreTransferActionTest` | Happy path output mapping, Schedule II output, null confirm default |
| `InventoryPositionSelector` | `InterStoreTransferServiceTest`, `InterStoreTransferActionTest` | `getById()` exercised in every test; `findSurplusSources()` exercised in happy path, cold-chain, and expiry tests |
| `ISTTestDataFactory` | All test classes | Every method called multiple times across all tests |

---

## Test Data Strategy

All test data is created using `ISTTestDataFactory` — no `@TestSetup` methods are used. Each test method creates its own isolated data set to avoid cross-test dependencies.

Key patterns:
- Store names include the test context (e.g., `'CVS Downtown'`, `'CVS Westside'`) for readable assertions
- DEA registration values are unique per test (e.g., `'DEA-TARGET-001'`, `'DEA-SOURCE-001'`)
- Medication names include suffixes to avoid uniqueness conflicts on `NDC__c` (e.g., `'Mounjaro-Action'`, `'Mounjaro-Execute'`)
- Expiry dates are set relative to today using `daysToExpiry` parameter — tests for expiry filtering use values below (10 days) and above (90 days) the 30-day threshold

---

## Async Testing Notes

The project does not currently use any asynchronous Apex patterns (Queueable, Batch, Schedulable, Future). All logic executes synchronously within the invocable method call. `Test.startTest()` / `Test.stopTest()` is used in all tests to reset governor limits and ensure DML finalization.
