---
layout: default
title: Deployment
parent: Setup
nav_order: 1
---

# Deployment Guide

How to deploy AgentforcePharmaGrid to a scratch org, sandbox, or production org.

---

## Prerequisites

- **Salesforce CLI** (`sf`) installed and authenticated. See https://developer.salesforce.com/tools/sfdxcli for install instructions.
- **A target org with Agentforce enabled.** Required so the admin-authored `IST_Inventory_Recommendation` `GenAiPromptTemplate` can be created in Prompt Builder after deploy. `PostInstallScript.verifyPromptTemplate()` queries the `AiPrompt` SObject — if Agentforce is not enabled the query throws and the install logs a `LoggingLevel.INFO` message instead of failing.
- **`sourceApiVersion` 66.0** or later (the project's declared version in `sfdx-project.json`). Apex class meta XMLs declare `apiVersion 65.0` which is compatible.
- **A user with permission to deploy custom objects, Apex, Flows, Permission Sets, and Layouts**, and to author `GenAiPromptTemplate` records in Prompt Builder. A System Administrator profile is sufficient.

---

## Deploy to a scratch org

```bash
# 1. Create a 30-day scratch org with Agentforce enabled
sf org create scratch --definition-file config/project-scratch-def.json --alias ist-dev --duration-days 30

# 2. Push source
sf project deploy start --source-dir force-app --target-org ist-dev

# 3. Assign the permission set
sf org assign permset --name IST_Ops_User --target-org ist-dev

# 4. Open the org
sf org open --target-org ist-dev
```

> The scratch org definition uses the `Einstein1AIPlatform` feature with Agentforce and Einstein GPT platform settings enabled. The requester Dev Hub must support 30-day scratch orgs and have scratch org capacity available.

---

## Deploy to a sandbox

```bash
# 1. Authenticate
sf org login web --instance-url https://test.salesforce.com --alias ist-sandbox

# 2. Validate (check-only deploy) first
sf project deploy validate --source-dir force-app --target-org ist-sandbox --test-level RunLocalTests

# 3. If validation passes, deploy
sf project deploy start --source-dir force-app --target-org ist-sandbox --test-level RunLocalTests

# 4. Assign the permission set
sf org assign permset --name IST_Ops_User --target-org ist-sandbox
```

> The project ships four test classes — `InterStoreTransferServiceTest`, `InterStoreTransferActionTest`, `InventoryPositionSelectorTest`, `PostInstallScriptTest` — so `--test-level RunLocalTests` passes out of the box. See [Testing Guide](testing.html) for per-class coverage targets.

---

## Deploy to production

Production deploys require a `RunLocalTests` (or `RunSpecifiedTests`) test level *and* ≥75% coverage across the affected classes. The four shipped test classes exceed that threshold, so:

```bash
# 1. Authenticate
sf org login web --alias ist-prod

# 2. Validate
sf project deploy validate --source-dir force-app --target-org ist-prod --test-level RunLocalTests

# 3. Quick-deploy after a clean validation (within 10 days)
sf project deploy quick --job-id <validation-job-id> --target-org ist-prod
```

---

## Post-deploy steps

If you installed via a managed package, `PostInstallScript.onInstall()` seeds demo data, assigns the permission set, and runs the prompt-template check. Step 1 below still requires manual authoring in Prompt Builder.

1. **Author the `IST_Inventory_Recommendation` prompt template manually.** Setup → Prompt Builder → New → follow [Create the Prompt Template](create-prompt-template.html) for the full system prompt and rule set. `PostInstallScript.verifyPromptTemplate()` logs `LoggingLevel.WARN` until the template exists in the org.
2. **Activate the Flow.** Setup → Flows → `Execute_Inter_Store_Transfer` → Activate (if not already active per the source `<status>Active</status>`).
3. **Add the Grid to the record page.**
   - Open the `Inventory_Position_Record_Page` Lightning record page in App Builder.
   - Add an **Agentforce Grid** component.
   - Bind the Grid to the `Inventory_Transfer_Ops` list view.
   - Bind the Recommendation column to the `IST_Inventory_Recommendation` prompt template (display field: `Recommendation_Preview__c`).
   - Add a per-row action button labelled **Transfer/Optimize**, type **Flow**, target `Execute_Inter_Store_Transfer`, with input mapping `inventoryPositionId ← {Salesforce.Id}`.
4. **Assign the `IST_Ops_User` permission set** to ops users:

   ```bash
   sf org assign permset --name IST_Ops_User --on-behalf-of ops-user@example.com --target-org ist-prod
   ```

5. **(Optional) Seed demo data** — see [scripts/DEMO_PLAYBOOK.md](https://github.com/jayavardhan-raju/AgentforcePharmaGrid/blob/main/scripts/DEMO_PLAYBOOK.md) for re-runnable anonymous Apex scripts that create realistic data for the three demo scenarios (happy path cold-chain transfer, Schedule II compliance block, distributor fallback on near-expiry).

---

## Verifying the deploy

Quick smoke checks:

```bash
# All four custom objects present
sf data query --query "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN ('Pharmacy_Store__c','Medication__c','Inventory_Position__c','Transfer_Log__c')" --target-org ist-dev

# Apex classes deployed (production + tests)
sf data query --query "SELECT Name FROM ApexClass WHERE Name IN ('InterStoreTransferService','InterStoreTransferAction','InventoryPositionSelector','PostInstallScript','ISTTestDataFactory','InterStoreTransferServiceTest','InterStoreTransferActionTest','InventoryPositionSelectorTest','PostInstallScriptTest')" --target-org ist-dev

# Prompt template was authored manually (returns 1 row once you complete create-prompt-template.html)
sf data query --query "SELECT DeveloperName, MasterLabel, ActiveVersion FROM AiPrompt WHERE DeveloperName = 'IST_Inventory_Recommendation'" --target-org ist-dev

# Flow active
sf data query --query "SELECT Status FROM FlowDefinitionView WHERE ApiName = 'Execute_Inter_Store_Transfer'" --target-org ist-dev
```

Then seed the demo data (run all three in order — script 3 looks up the records from scripts 1 and 2 by name):

```bash
sf apex run --file scripts/apex/1_Create_Pharmacy_Stores.apex     --target-org ist-dev
sf apex run --file scripts/apex/2_Create_Medications.apex          --target-org ist-dev
sf apex run --file scripts/apex/3_Create_Inventory_Positions.apex  --target-org ist-dev
```

Each script's `System.debug` output lists the records it created. Open the `Inventory_Position__c` tab (filtered to the `Inventory_Transfer_Ops` list view) to see the Agentforce Grid populated with the seeded data. See [scripts/DEMO_PLAYBOOK.md](https://github.com/jayavardhan-raju/AgentforcePharmaGrid/blob/main/scripts/DEMO_PLAYBOOK.md) for the six scenarios these scripts set up.

---

## Common deploy issues

| Symptom | Likely cause | Fix |
|---|---|---|
| Grid Recommendation column is blank | Prompt template not yet authored, or its `ActiveVersion` is not `1` (i.e. not activated in Prompt Builder) | Follow [Create the Prompt Template](create-prompt-template.html) and click **Activate** in Prompt Builder. Re-check via `SELECT ActiveVersion FROM AiPrompt WHERE DeveloperName = 'IST_Inventory_Recommendation'` |
| `PostInstallScript` debug log shows `WARN: Prompt Template IST_Inventory_Recommendation not found` | The template was not yet authored when the install handler ran | Author it via the steps above; the warning is informational and never blocks an install |
| Flow deploy fails on `actionName = InterStoreTransferAction` | Apex class not yet deployed when Flow validates | Deploy in order: classes first, then flows. Source-format `sf project deploy start` handles this automatically; manifest deploys may need `--ignore-conflicts` and a second pass |
| Permission set assignment skipped | User already has it | `assignPermissionSet()` queries `PermissionSetAssignment` and skips on duplicate; this is intentional |
| `Recommendation_Preview__c` shows blank in Grid after click | Field-level security not granted on the field for the running user | Confirm the user is on `IST_Ops_User` permset; check `Schema.sObjectType.Inventory_Position__c.fields.Recommendation_Preview__c.isUpdateable()` returns true for that user |
| `RunLocalTests` reports < 75% coverage | `--source-dir` excluded one of the test classes | Confirm all four test classes (`InterStoreTransferServiceTest`, `InterStoreTransferActionTest`, `InventoryPositionSelectorTest`, `PostInstallScriptTest`) are present under `force-app/main/default/classes/` |
