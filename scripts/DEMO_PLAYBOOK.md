# AgentforcePharmaGrid Demo Playbook

## Overview

This playbook accompanies three anonymous Apex scripts in `scripts/apex/`. Each script seeds isolated, demo-named records (no clash with other org data), invokes the live `InterStoreTransferService` end-to-end, and asserts the post-call state with `System.debug` markers prefixed `[OK]`, `[VERIFY]`, and `[ERROR]`.

The scripts are **demo seeders, not unit tests**. They use real DML on real records and run synchronously in the script's own transaction. Their job is to give a stakeholder a Lightning record-page URL they can click to see the Agentforce Grid populated and the Transfer Log related list reflecting the scenario's outcome.

| Script | Scenario | Code Path Exercised |
|---|---|---|
| `TC1_HappyPath_ColdChainTransfer.apex` | Cold-chain medication, eligible source found, 50-unit transfer executes | `evaluate` → `findSurplusSources` → `selectBestSource` → `calculateTransferQty` → `buildRecommendation` (dry-run) → `executeTransfer` |
| `TC2_ScheduleII_ComplianceBlock.apex` | Schedule II Adderall blocked at compliance gate | `evaluate` → `isScheduleII` → `logComplianceBlock` |
| `TC3_DistributorFallback_NearExpiry.apex` | Two ineligible candidates (near-expiry + non-cold-chain) → distributor fallback | `evaluate` → `findSurplusSources` → `selectBestSource` returns null |

---

## Prerequisites

1. Deploy AgentforcePharmaGrid to your org (see [Deployment Guide](../docs/setup/deployment.md)).
2. Assign the `IST_Ops_User` permission set to the user running the script:
   ```bash
   sf org assign permset --name IST_Ops_User --target-org your-org
   ```
3. The Agentforce Grid must be on the `Inventory_Position__c` record page if you want to *visually* verify each scenario — but the scripts themselves don't depend on the Grid; they assert state via SOQL and `System.debug`.

---

## How to Run

### Option A: Salesforce CLI (recommended)

```bash
sf apex run --file scripts/apex/TC1_HappyPath_ColdChainTransfer.apex --target-org your-org
sf apex run --file scripts/apex/TC2_ScheduleII_ComplianceBlock.apex   --target-org your-org
sf apex run --file scripts/apex/TC3_DistributorFallback_NearExpiry.apex --target-org your-org
```

Each call returns the script's `System.debug` output inline. Look for `[TC1 COMPLETE]` / `[TC2 COMPLETE]` / `[TC3 COMPLETE]` and the Lightning record-page URL printed on the last line.

### Option B: VS Code (Salesforce Extensions)

1. Open the `.apex` file in VS Code.
2. Highlight the entire file contents (Ctrl/Cmd-A).
3. Open the Command Palette (Ctrl/Cmd-Shift-P).
4. Run **SFDX: Execute Anonymous Apex with Currently Selected Text**.
5. Pick the target org if prompted.
6. View output in the Output panel under "Salesforce CLI".

### Option C: Developer Console

1. Setup → Developer Console.
2. **Debug** → **Open Execute Anonymous Window**.
3. Paste the entire script contents.
4. Tick **Open Log** (so the debug log opens automatically).
5. Click **Execute**.
6. In the Log Inspector, filter the **Debug Only** view by `[OK]`, `[VERIFY]`, or `[TC` to follow the script's progress.

---

## What Each Script Does

### TC1: Happy Path Cold-Chain Transfer

Demonstrates the full transfer workflow when every eligibility filter passes.

1. Creates 2 cold-chain-capable Bay Area stores (`TC1 Target SF Downtown`, `TC1 Source SF Westside`), both with valid `DEA_Registration__c` and `Is_Active__c = true`.
2. Creates 1 medication (`TC1 Mounjaro 5mg`, `Cold_Chain_Required__c = true`, `DEA_Schedule__c = 'None'`).
3. Creates 2 `Inventory_Position__c` rows: target qty=0/safety=50 (critical); source qty=200/safety=50/expiry+90d.
4. **Calls `evaluate(targetId, confirm=false)`** — dry-run.
   - Service: load → not Schedule II → find candidates (1 hit) → `selectBestSource` passes all filters → `calculateTransferQty`: `proposed = (200-50)*50/100 = 75`, `targetNeed = 50-0 = 50`, **`min(75, 50) = 50`**.
   - Service writes `Recommendation__c` (full text) and `Recommendation_Preview__c` (truncated to 255 if needed).
   - Returns `success=true`, `recommendedQty=50`, `uhText` ending in *"Shall I proceed with this transfer?"*.
5. **Calls `evaluate(targetId, confirm=true)`** — execute.
   - Service: same path through to `executeTransfer`.
   - Inside savepoint: source qty 200→150, target qty 0→50, `Transfer_Log__c` inserted with `Transfer_Status__c = 'Completed'`, `Quantity_Transferred__c = 50`, full `Notes__c`.
6. Re-queries and asserts: target qty=50, source qty=150, log status=Completed.

**Demo URL:** the script's last `System.debug` prints `/lightning/r/Inventory_Position__c/<targetId>/view`. Open it to see the Agentforce Grid row reflecting completion preview, plus the Transfer Logs related list with the new Completed entry.

### TC2: Schedule II Compliance Hard Stop

Demonstrates that the compliance gate fires *before* any source search, no matter how attractive the available surplus is.

1. Creates 2 stores (`TC2 Target SF Downtown`, `TC2 Source SJ Central`) — both fully eligible on every dimension. The script intentionally makes the source attractive so it's clear the block is policy-driven, not data-driven.
2. Creates 1 Schedule II medication (`TC2 Adderall XR 30mg`, `DEA_Schedule__c = 'II'`).
3. Creates 2 `Inventory_Position__c` rows: target qty=5/safety=30; source qty=100/safety=20/expiry+150d.
4. **Calls `evaluate(targetId, confirm=false)`**.
   - Service: load → `isScheduleII` returns `true` → `logComplianceBlock` writes `Transfer_Log__c` with `Source_Store__c = null`, `Quantity_Transferred__c = 0`, `Transfer_Status__c = 'Blocked'`, `Notes__c = "COMPLIANCE BLOCK: DEA Schedule II - TC2 Adderall XR 30mg. DEA Form 222 required. Automated transfer denied by Agentforce Grid."`
   - Returns `success=false`, all source/qty fields null, `uhText` containing *"Compliance Restriction: Schedule II controlled substance detected"* and *"Manual DEA Form 222 is required"*.
5. Asserts: source qty unchanged at 100, target qty unchanged at 5, `Recommendation__c` not written, exactly one Blocked log row exists.

**Demo URL:** target Inventory Position record. The Transfer Logs related list shows one entry with status **Blocked**, no source store, and a note explaining the DEA Form 222 requirement.

### TC3: Distributor Fallback (Near-Expiry Exclusion)

Demonstrates the no-eligible-source path. Both candidate sources fail eligibility — for *different* reasons — proving each filter is independent.

1. Creates 3 stores: target (`TC3 Target SJ Central`, cold-chain capable), and two candidates that each fail one filter:
   - `TC3 Source SF Downtown NearExpiry` — cold-chain OK, DEA reg OK, but its Inventory Position has `Expiry_Date__c = today + 15` (less than `MIN_DAYS_TO_EXPIRY` of 30).
   - `TC3 Source Oakland NoColdChain` — `Cold_Chain_Capable__c = false`, but the medication requires cold chain.
2. Creates 1 cold-chain medication (`TC3 Ozempic 1mg`, `Cold_Chain_Required__c = true`).
3. Creates 3 `Inventory_Position__c` rows.
4. **Calls `evaluate(targetId, confirm=false)`**.
   - Service: load → not Schedule II → `findSurplusSources` returns 2 candidates (both pass the SOQL `Quantity__c > minQty` and `Is_Active__c = true` filters) → `selectBestSource` walks the list:
     - First candidate (`NearExpiry`, qty=100): cold-chain OK, DEA reg OK, but `today.daysBetween(today+15) = 15 < 30` → **skipped**.
     - Second candidate (`NoColdChain`, qty=80): `coldChainNeeded = true && !candidate.Store__r.Cold_Chain_Capable__c` → **skipped**.
   - `selectBestSource` returns null → service returns the distributor-fallback message.
5. Returns `success=false`, all source/qty fields null, `uhText` containing *"No suitable source store found for TC3 Ozempic 1mg"* and *"Recommended next action: Place an emergency order with your primary distributor."*
6. Asserts: all 3 inventory quantities unchanged, no `Recommendation__c` written, **no `Transfer_Log__c` written** (this is the only path where the service neither writes a log nor mutates inventory).

**Demo URL:** target Inventory Position record. Status shows LOW/orange. Recommendation Preview is blank. No Transfer Log entries.

---

## Cleanup

To wipe all demo data created by all three scripts in one go, run this anonymous Apex:

```apex
Set<String> demoStoreNames = new Set<String>{
    'TC1 Target SF Downtown', 'TC1 Source SF Westside',
    'TC2 Target SF Downtown', 'TC2 Source SJ Central',
    'TC3 Target SJ Central', 'TC3 Source SF Downtown NearExpiry', 'TC3 Source Oakland NoColdChain'
};
Set<String> demoMedNames = new Set<String>{
    'TC1 Mounjaro 5mg', 'TC2 Adderall XR 30mg', 'TC3 Ozempic 1mg'
};

List<Transfer_Log__c> logs = [
    SELECT Id FROM Transfer_Log__c
    WHERE Inventory_Position__r.Store__r.Name IN :demoStoreNames
       OR Source_Store__r.Name              IN :demoStoreNames
       OR Target_Store__r.Name              IN :demoStoreNames
];
if (!logs.isEmpty()) { delete logs; System.debug('Deleted Transfer_Log__c: ' + logs.size()); }

List<Inventory_Position__c> invs = [
    SELECT Id FROM Inventory_Position__c
    WHERE Store__r.Name IN :demoStoreNames OR Medication__r.Name IN :demoMedNames
];
if (!invs.isEmpty()) { delete invs; System.debug('Deleted Inventory_Position__c: ' + invs.size()); }

List<Medication__c> meds = [SELECT Id FROM Medication__c WHERE Name IN :demoMedNames];
if (!meds.isEmpty()) { delete meds; System.debug('Deleted Medication__c: ' + meds.size()); }

List<Pharmacy_Store__c> stores = [SELECT Id FROM Pharmacy_Store__c WHERE Name IN :demoStoreNames];
if (!stores.isEmpty()) { delete stores; System.debug('Deleted Pharmacy_Store__c: ' + stores.size()); }

System.debug('[CLEANUP COMPLETE]');
```

Each TC script also runs its *own* cleanup at the top, so re-running a single script is always safe — but the standalone snippet above lets you nuke all demo data in one shot when you're done with the demo.

---

## Important Notes

- **Demo seeders, not unit tests.** These scripts use real DML on real records. Don't run them in production. They live in `scripts/apex/` precisely because they are *not* part of the deployable metadata — running `sf project deploy` will not push them.
- **No async to bypass.** This project doesn't use Queueable, Batch, Future, or @Schedulable, so there's no async timing to work around. Everything in `evaluate()` runs synchronously inside the script's transaction.
- **The TC scripts are demos, but the actual unit tests are still missing.** See [Testing Guide](../docs/setup/testing.md) for the test class scenarios that need to be authored before a production deploy is possible.
- **PostInstallScript creates similar-but-separate data.** If you've installed via a managed package, you'll already have records named `CVS Downtown SF`, `CVS Westside SF`, etc. The TC scripts use `TC1`/`TC2`/`TC3`-prefixed names to avoid colliding with that data.
- **Schedule II `Transfer_Log__c` is durable.** Cleanup deletes it for re-runs, but in a real org you would never delete a compliance audit log. The cleanup-then-recreate pattern is purely for demo convenience.
