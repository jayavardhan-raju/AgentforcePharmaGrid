# AgentforcePharmaGrid Demo Playbook

## Overview

This playbook accompanies the three anonymous Apex **seeder** scripts in `scripts/apex/`. Run in order, they build a complete, realistic demo dataset — **6 pharmacy stores, 6 medications, and 15 inventory positions** spread across **6 scenarios** that exercise every code path in `InterStoreTransferService`.

The scripts are **demo seeders, not unit tests, and not the live service**. They only insert records — they do not call `InterStoreTransferService.evaluate()`. Once the data is in place, you drive each scenario yourself by clicking the **Transfer/Optimize** button on the Agentforce Grid (which runs the service through the `Execute_Inter_Store_Transfer` Flow). The seed data is hand-tuned so each scenario produces a different, predictable outcome.

This is the same dataset that `PostInstallScript.onInstall()` creates automatically on a managed-package install. The scripts let you seed (or re-seed) the data into a scratch org or sandbox where you deployed from source.

| Order | Script | Creates | Purpose |
|---|---|---|---|
| 1 | `1_Create_Pharmacy_Stores.apex` | 6 `Pharmacy_Store__c` | Stores with varied cold-chain, DEA-registration, and active flags to exercise every source-eligibility filter |
| 2 | `2_Create_Medications.apex` | 6 `Medication__c` | Medications spanning Schedule II/IV/None and cold-chain-required/not |
| 3 | `3_Create_Inventory_Positions.apex` | 15 `Inventory_Position__c` | Inventory across 6 scenarios; queries the records from scripts 1 & 2 by name |

> **Run them in order.** Script 3 looks up stores and medications **by name** and throws `IllegalArgumentException` listing exactly what's missing if you skip script 1 or 2.

---

## Prerequisites

1. Deploy AgentforcePharmaGrid to your org (see [Deployment Guide](../docs/setup/deployment.md)).
2. Assign the `IST_Ops_User` permission set to the user running the scripts:
   ```bash
   sf org assign permset --name IST_Ops_User --target-org your-org
   ```
3. To *visually* demo each scenario, add the Agentforce Grid (bound to the `Inventory_Transfer_Ops` list view) to the `Inventory_Position__c` record page, and create the `IST_Inventory_Recommendation` prompt template per [Create the Prompt Template](../docs/setup/create-prompt-template.md). The seeder scripts themselves don't depend on the Grid or the template.

---

## How to Run

### Option A: Salesforce CLI (recommended)

```bash
sf apex run --file scripts/apex/1_Create_Pharmacy_Stores.apex     --target-org your-org
sf apex run --file scripts/apex/2_Create_Medications.apex          --target-org your-org
sf apex run --file scripts/apex/3_Create_Inventory_Positions.apex  --target-org your-org
```

Each call prints its `System.debug` output inline — the created record IDs, names, and key flags — so you can confirm the seed succeeded before moving on.

### Option B: VS Code (Salesforce Extensions)

1. Open the `.apex` file in VS Code.
2. Highlight the entire file contents (Ctrl/Cmd-A).
3. Open the Command Palette (Ctrl/Cmd-Shift-P).
4. Run **SFDX: Execute Anonymous Apex with Currently Selected Text**.
5. Pick the target org if prompted; repeat for scripts 1 → 2 → 3.

### Option C: Developer Console

1. Setup → Developer Console.
2. **Debug** → **Open Execute Anonymous Window**.
3. Paste a script's contents, tick **Open Log**, and click **Execute**.
4. Run scripts 1, 2, then 3 in that order.

---

## What Each Script Does

### Script 1 — `1_Create_Pharmacy_Stores.apex`

Inserts **6 stores** across two districts. The variety is what makes the source-eligibility filters demonstrable:

| Store | District | Cold-Chain Capable | DEA Registration | Active |
|---|---|---|---|---|
| CVS Downtown SF | District 1 - Bay Area | ✓ | `DEA-SF-DT-001` | ✓ |
| CVS Westside SF | District 1 - Bay Area | ✓ | `DEA-SF-WS-002` | ✓ |
| CVS Eastside Oakland | District 1 - Bay Area | ✗ | `DEA-OAK-ES-003` | ✓ |
| CVS San Jose Central | District 2 - South Bay | ✓ | `DEA-SJ-CT-004` | ✓ |
| CVS Sunnyvale | District 2 - South Bay | ✓ | *(blank)* | ✓ |
| CVS Palo Alto (Closed) | District 2 - South Bay | ✓ | `DEA-PA-CL-006` | ✗ |

- **CVS Eastside Oakland** is *not* cold-chain capable → filtered out as a source for cold-chain meds.
- **CVS Sunnyvale** has a blank `DEA_Registration__c` → filtered out by `selectBestSource()`.
- **CVS Palo Alto (Closed)** is inactive → excluded by the `findSurplusSources()` SOQL `WHERE Store__r.Is_Active__c = true`.

### Script 2 — `2_Create_Medications.apex`

Inserts **6 medications** spanning the regulatory/handling matrix:

| Medication | NDC | DEA Schedule | Cold-Chain Required |
|---|---|---|---|
| Mounjaro 5mg | `00002-1523-80` | None | ✓ |
| Ozempic 1mg | `00169-4132-12` | None | ✓ |
| Adderall XR 30mg | `54092-0391-01` | **II** | ✗ |
| Xanax 0.5mg | `00009-0055-01` | IV | ✗ |
| Lisinopril 10mg | `00093-1044-01` | None | ✗ |
| Amoxicillin 500mg | `65862-0015-01` | None | ✗ |

`NDC__c` is unique, so re-running this script without cleaning up first will raise a `DUPLICATE_VALUE` error — run the cleanup below before re-seeding.

### Script 3 — `3_Create_Inventory_Positions.apex`

Queries the stores and medications by name (validating all are present), then inserts **15 inventory positions** that set up the 6 scenarios below. Each scenario is designed so that clicking **Transfer/Optimize** on the *target* (low/out-of-stock) row produces a specific outcome.

| # | Scenario | Target (critical) row | What happens on Transfer/Optimize |
|---|---|---|---|
| 1 | **Happy path (cold chain)** | Mounjaro 5mg @ CVS Downtown SF (qty 0 / safety 50) | Westside SF (qty 200) is an eligible cold-chain source → recommends **50 units**, executes atomically, writes a `Completed` Transfer Log |
| 2 | **Schedule II block** | Adderall XR 30mg @ CVS Downtown SF (qty 5 / safety 30) | Compliance gate fires before any source search → DEA Form 222 message; a `Blocked` Transfer Log is written |
| 3 | **Distributor fallback** | Lisinopril 10mg @ CVS Downtown SF (qty 0 / safety 60) | Only other store (Westside, qty 30) is below the required surplus → no eligible source → distributor-fallback message |
| 4 | **Near-expiry exclusion** | Ozempic 1mg @ CVS San Jose Central (qty 5 / safety 40) | Highest-stock source (Downtown SF, qty 100) expires in 15 days (< 30) → skipped; Westside (qty 80) is eligible → recommends a transfer |
| 5 | **Schedule IV allowed** | Xanax 0.5mg @ CVS Eastside Oakland (qty 10 / safety 40) | Schedule IV is *not* blocked → San Jose Central (qty 150) is an eligible source → standard transfer |
| 6 | **Multiple healthy sources** | Amoxicillin 500mg @ CVS Sunnyvale (qty 0 / safety 50) | Two stocked stores (Downtown SF qty 300, San Jose qty 120) → highest-surplus eligible source wins |

**Demo flow:** open the `Inventory_Position__c` tab / Agentforce Grid, filter to the `Inventory_Transfer_Ops` list view, find the critical row for the scenario you want to show, and click **Transfer/Optimize**. The agent surfaces the dry-run recommendation (`uhText`) and asks you to confirm; on confirmation the transfer executes and the Transfer Logs related list updates.

---

## Cleanup

To wipe **all** seeded data (so you can re-run the scripts cleanly), use the bundled uninstall seeder:

```bash
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org your-org
```

It deletes in FK-safe order — Transfer Logs, then Inventory Positions, then Medications, then Pharmacy Stores. Or paste this equivalent inline:

```apex
delete [SELECT Id FROM Transfer_Log__c];
delete [SELECT Id FROM Inventory_Position__c];
delete [SELECT Id FROM Medication__c];
delete [SELECT Id FROM Pharmacy_Store__c];
System.debug('[CLEANUP COMPLETE]');
```

> **Note:** these `delete` statements remove **all** records of each object, including any you created by hand. In a shared org, scope the queries to the demo store/medication names instead. Never delete `Transfer_Log__c` records in a real production org — they are the DEA compliance audit trail.

---

## Important Notes

- **Seeders, not unit tests.** These scripts use real DML on real records. Don't run them in production. They live in `scripts/apex/` precisely because they are *not* deployable metadata — `sf project deploy` will not push them.
- **No async to bypass.** This project uses no Queueable, Batch, Future, or `@Schedulable` processing, so there is no async timing to work around. The service runs synchronously when the Grid button invokes it.
- **Same data as `PostInstallScript`.** A managed-package install runs `PostInstallScript.onInstall()`, which seeds this exact dataset and assigns `IST_Ops_User` automatically. These scripts are for source-deploy orgs (scratch/sandbox) where the post-install handler doesn't fire.
- **The deployable test suite is separate.** `InterStoreTransferServiceTest`, `InterStoreTransferActionTest`, `InventoryPositionSelectorTest`, and `PostInstallScriptTest` (under `force-app/main/default/classes/`) provide production-deploy coverage. See the [Testing Guide](../docs/setup/testing.md). The seeder scripts here are *not* part of that coverage.
- **Prompt template is admin-authored.** The Grid's Recommendation column shows `IST_Inventory_Recommendation` output, created manually in Prompt Builder per [docs/setup/create-prompt-template.md](../docs/setup/create-prompt-template.md). Until it exists, the column simply shows the `Recommendation_Preview__c` text the service writes after a dry-run.
