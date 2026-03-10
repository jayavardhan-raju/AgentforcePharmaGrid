---
layout: default
title: Testing
parent: Setup
nav_order: 2
---

# Testing Guide

The project includes two test classes and a shared test data factory, targeting ≥90% code coverage across all production classes.

---

## Running the Tests

### CLI

```bash
# Run all IST test classes
sf apex test run \
  -n InterStoreTransferServiceTest,InterStoreTransferActionTest \
  -r human \
  -c \
  --detailed-coverage \
  -o IST
```

### Developer Console

1. Open Developer Console → Test → New Run
2. Select `InterStoreTransferServiceTest` and `InterStoreTransferActionTest`
3. Click Run

---

## Test Coverage Map

### InterStoreTransferServiceTest (8 test methods)

| Test Method | Classes Covered | Scenario |
|-------------|----------------|----------|
| `testEvaluate_HappyPath_DryRun_ReturnsRecommendation` | Service (`evaluate`, `selectBestSource`, `calculateTransferQty`, `buildRecommendation`), Selector (`getById`, `findSurplusSources`) | TC1: Non-controlled med, eligible source exists, dry-run returns recommendation with "Shall I proceed?" |
| `testEvaluate_HappyPath_Execute_CreatesTransferLog` | Service (`evaluate`, `executeTransfer`), Selector | TC1: confirm=true, atomic DML, Transfer_Log created, inventory quantities updated |
| `testEvaluate_ScheduleII_DryRun_HardStop` | Service (`evaluate`, `isScheduleII`, `logComplianceBlock`), Selector | TC2: DEA Schedule II, success=false, no "Shall I proceed?", Transfer_Log status=Blocked |
| `testEvaluate_ScheduleII_ConfirmTrue_StillBlocked` | Service (`evaluate`, `isScheduleII`) | TC2: confirm=true does NOT bypass Schedule II block, no Completed log |
| `testEvaluate_NoSuitableSource_ReturnsFallback` | Service (`evaluate`), Selector (`findSurplusSources` returns empty) | TC3: No source inventory exists, distributor fallback, no "Shall I proceed?" |
| `testEvaluate_NoSuitableSource_ColdChainMismatch` | Service (`selectBestSource` cold-chain filter) | Source store not cold-chain capable, medication requires cold chain, source excluded |
| `testEvaluate_NullId_ReturnsErrorGracefully` | Service (`evaluate`), Selector (`getById` throws) | Null ID passed, graceful error return instead of unhandled exception |
| `testEvaluate_ExpiredSourceStock_Excluded` | Service (`selectBestSource` expiry filter) | Source stock expires in 10 days (< 30d threshold), excluded from candidates |

### InterStoreTransferActionTest (3 test methods)

| Test Method | Classes Covered | Scenario |
|-------------|----------------|----------|
| `testAction_HappyPath_DryRun_ReturnsOutput` | Action (`execute`, `ActionInput`, `ActionOutput`) → Service | Validates Invocable wiring: input/output mapping, success=true, uhText populated |
| `testAction_ScheduleII_ReturnsComplianceBlock` | Action → Service (compliance path) | Validates Schedule II uhText flows through Action layer correctly |
| `testAction_NullConfirm_DefaultsToFalse` | Action (null handling) | confirm=null defaults to false (dry-run), no Completed Transfer_Log created |

---

## Test Data Factory

`ISTTestDataFactory` provides three reusable methods used by both test classes:

| Method | Parameters | Creates |
|--------|-----------|---------|
| `createStore(name, coldChain, deaReg, active)` | Store name, cold-chain flag, DEA registration, active flag | `Pharmacy_Store__c` in District 1, SF coordinates |
| `createMedication(name, deaSchedule, coldChain)` | Med name, DEA schedule, cold-chain flag | `Medication__c` with auto-generated NDC (`NDC-[name]-001`) |
| `createInventory(storeId, medId, qty, safetyStock, daysToExpiry)` | Store ID, Medication ID, quantity, safety stock, days to expiry | `Inventory_Position__c` with computed expiry date |

---

## Test Case Scenarios (Functional)

These are the three functional test scenarios used for both Apex tests and Agentforce Grid testing:

### TC1: Happy Path (Mounjaro Transfer)

**Setup:** CVS Downtown has 0 units of Mounjaro (non-controlled, cold-chain). Walgreens North has 250 units (50d to expiry), CVS Westside has 200 units (42d to expiry). Both sources are cold-chain capable with DEA registration.

**Expected dry-run:** success=true. Walgreens North selected (highest qty, 250 > 200). Transfer qty = min((250-50)×50%, 50-0) = min(100, 50) = 50 units. uhText contains "Shall I proceed?"

**Expected execution:** Source qty decremented, target qty incremented, Transfer_Log (Completed) created with audit details.

### TC2: Schedule II Block (Adderall)

**Setup:** CVS Downtown has 0 units of Adderall (DEA Schedule II). A source exists with 200 units.

**Expected:** success=false. Compliance block fires before any source search. uhText references "Schedule II" and "DEA Form 222". Transfer_Log (Blocked) created. No "Shall I proceed?" prompt. Even confirm=true is blocked.

### TC3: No Eligible Source (Mounjaro 5mg)

**Setup:** CVS Downtown has 0 units of Mounjaro 5mg (non-controlled, cold-chain). CVS Westside has 70 units (20d expiry), Walgreens North has 300 units (15d expiry). Both sources are excluded by the 30-day expiry threshold.

**Expected:** success=false. uhText contains "No suitable source store found" and recommends distributor order. No "Shall I proceed?" prompt.
