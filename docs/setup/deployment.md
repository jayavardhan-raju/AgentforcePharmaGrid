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
- **A target org with Agentforce enabled.** The `IST_Inventory_Recommendation` prompt template requires the `AiPrompt` SObject. If Agentforce is not enabled, the prompt template won't deploy and `PostInstallScript.verifyPromptTemplate()` will log an info-level message rather than fail.
- **API v65.0** or later. The project's source uses v65 features; older orgs may need an API upgrade in `sfdx-project.json`.
- **A user with permission to deploy custom objects, Apex, Flows, and Prompt Templates.** A System Administrator profile is sufficient.

---

## Deploy to a scratch org

```bash
# 1. Create a scratch org with Agentforce enabled
sf org create scratch --definition-file config/project-scratch-def.json --alias ist-dev --duration-days 7

# 2. Push source
sf project deploy start --source-dir force-app --target-org ist-dev

# 3. Assign the permission set
sf org assign permset --name IST_Ops_User --target-org ist-dev

# 4. Open the org
sf org open --target-org ist-dev
```

> The scratch org definition file is not in the uploaded `force-app/` archive — you'll need to add `config/project-scratch-def.json` with the `Agentforce` and `EinsteinAI` features enabled before step 1 works.

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

> **Heads up:** `--test-level RunLocalTests` will fail today because no test class exists. Either use `--test-level NoTestRun` for sandbox (not allowed for production) or author a test class first. See [Testing Guide](testing.html).

---

## Deploy to production

Production deploys require a `RunLocalTests` (or `RunSpecifiedTests`) test level *and* ≥75% coverage across the affected classes. Until a test class is added, the production deploy will fail.

When the test class is in place:

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

These steps configure the Agentforce Grid and verify the prompt template. If you installed via a managed package, `PostInstallScript.onInstall()` handles steps 1, 2, 4, and 5 automatically.

1. **Verify the prompt template.** Setup → Prompt Builder → look for **IST Inventory Recommendation** with `activeVersion = 1` and status `Published`.
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

5. **(Optional) Seed demo data** — see [scripts/DEMO_PLAYBOOK.md](https://github.com/jayavardhan-raju/AgentforcePharmaGrid/blob/main/scripts/DEMO_PLAYBOOK.md) for re-runnable anonymous Apex scripts that create realistic data for the four scenarios (happy path, Schedule II block, distributor fallback, near-expiry exclusion).

---

## Verifying the deploy

Quick smoke checks:

```bash
# All four custom objects present
sf data query --query "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName IN ('Pharmacy_Store__c','Medication__c','Inventory_Position__c','Transfer_Log__c')" --target-org ist-dev

# Apex classes deployed
sf data query --query "SELECT Name FROM ApexClass WHERE Name IN ('InterStoreTransferService','InterStoreTransferAction','InventoryPositionSelector','PostInstallScript','ISTTestDataFactory')" --target-org ist-dev

# Flow active
sf data query --query "SELECT Status FROM FlowDefinitionView WHERE ApiName = 'Execute_Inter_Store_Transfer'" --target-org ist-dev
```

Then run a demo script:

```bash
sf apex run --file scripts/apex/TC1_HappyPath_ColdChainTransfer.apex --target-org ist-dev
```

The script's final `System.debug` line includes a Lightning record-page URL — paste it into the browser to see the Agentforce Grid populated with the seeded data.

---

## Common deploy issues

| Symptom | Likely cause | Fix |
|---|---|---|
| Prompt template fails to deploy | Agentforce not enabled in target org | Enable Agentforce + Einstein in Setup, then redeploy `force-app/main/default/prompts/` |
| Flow deploy fails on `actionName = InterStoreTransferAction` | Apex class not yet deployed when Flow validates | Deploy in order: classes first, then flows. Source-format `sf project deploy start` handles this automatically; manifest deploys may need `--ignore-conflicts` and a second pass |
| Permission set assignment skipped | User already has it | `assignPermissionSet()` queries `PermissionSetAssignment` and skips on duplicate; this is intentional |
| `Recommendation_Preview__c` shows blank in Grid after click | Field-level security not granted on the field for the running user | Confirm the user is on `IST_Ops_User` permset; check `Schema.sObjectType.Inventory_Position__c.fields.Recommendation_Preview__c.isUpdateable()` returns true for that user |
