---
layout: default
title: Uninstall Guide
parent: Setup
nav_order: 99
---

# Uninstalling AgentforcePharmaGrid Package

This guide provides step-by-step instructions for completely removing the AgentforcePharmaGrid package from your Salesforce org.

## ⚠️ Important Warning

**Uninstalling will permanently delete:**
- All custom objects (`Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c`, `Transfer_Log__c`)
- All records in these objects (including any production data you've created)
- All Apex classes and test classes (`InterStoreTransferService` + Test, `InterStoreTransferAction` + Test, `InventoryPositionSelector` + Test, `PostInstallScript` + Test, `ISTTestDataFactory`)
- The `Execute_Inter_Store_Transfer` flow
- The `IST_Ops_User` permission set
- The `IST_Inventory_Recommendation` `GenAiPromptTemplate` — included in `destructiveChanges.xml` so the destructive deploy removes the admin-authored template if it exists in the org
- All page layouts and list views

**Before proceeding, ensure you have:**
- ✓ Backed up any data you want to keep
- ✓ Removed any dependencies on these objects (reports, dashboards, other code)
- ✓ Notified users who have the IST_Ops_User permission set
- ✓ Tested in a sandbox first if possible

---

## Uninstallation Process

The uninstallation follows a 3-step process:

1. **Delete Sample Data** — Remove all records created by PostInstallScript
2. **Remove Permission Sets** — Unassign permission sets from all users
3. **Deploy Destructive Changes** — Delete all metadata components

---

## Prerequisites

- Salesforce CLI installed
- Authenticated to your target org
- System Administrator or equivalent permissions

---

## Step 1: Delete Sample Data

Delete all sample data created by the post-install script.

### Run Data Deletion Script

```bash
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <your-org-alias>
```

### What This Does

- Deletes Transfer_Log__c records (if any)
- Deletes Inventory_Position__c records
- Deletes Medication__c records
- Deletes Pharmacy_Store__c records

### Expected Output

```
========================================
Starting Sample Data Deletion
========================================
Deleted 0 Transfer Log records
Deleted 15 Inventory Position records
Deleted 6 Medication records
Deleted 6 Pharmacy Store records
========================================
Sample Data Deletion Complete
========================================
Next Step: Run script 2_Remove_Permission_Sets.apex
```

> Counts assume the org has just the `PostInstallScript`-seeded data. If you've created additional records (or run the TC demo scripts), the numbers will be higher. The script deletes **all** records on these objects, so back up first if you have production data.

### ⚠️ Important Notes

- This script deletes **ALL** records in these objects, not just sample data
- If you have production data you want to keep, **do not run this script**
- Instead, manually delete only the sample records created by PostInstallScript

---

## Step 2: Remove Permission Set Assignments

Remove the IST_Ops_User permission set from all users.

### Run Permission Set Removal Script

```bash
sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <your-org-alias>
```

### What This Does

- Queries all users assigned to IST_Ops_User permission set
- Removes all permission set assignments
- Logs each user whose assignment was removed

### Expected Output

```
========================================
Starting Permission Set Removal
========================================
Found permission set: IST_Ops_User (ID: 0PS...)
Found 1 permission set assignment(s):
  - User: John Doe (john.doe@example.com)

Successfully removed 1 permission set assignment(s)
========================================
Permission Set Removal Complete
========================================
Next Step: Deploy destructiveChanges.xml to remove all metadata
```

### Why This Is Required

Permission sets cannot be deleted while they have active assignments. This script ensures all assignments are removed before metadata deletion.

---

## Step 3: Deploy Destructive Changes

Delete all package metadata components.

### Deploy Using Salesforce CLI

```bash
sf project deploy start \
  --manifest manifest/destructiveChanges.xml \
  --post-destructive-changes manifest/destructivePackage.xml \
  --target-org <your-org-alias>
```

### Alternative: Using VS Code

1. Right-click on `manifest/destructiveChanges.xml`
2. Select **SFDX: Deploy Manifest to Org**
3. Confirm the deployment

### What This Deletes

The `destructiveChanges.xml` file removes:

| Metadata Type | Components Deleted |
|--------------|-------------------|
| **Custom Objects** | `Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c`, `Transfer_Log__c` |
| **Apex Classes** | `InterStoreTransferAction` + Test, `InterStoreTransferService` + Test, `InventoryPositionSelector`, `ISTTestDataFactory`, `PostInstallScript` |
| **Flows** | `Execute_Inter_Store_Transfer` |
| **Permission Sets** | `IST_Ops_User` |
| **Gen AI Prompt Templates** | `IST_Inventory_Recommendation` (admin-authored — removed only if it exists in the org) |
| **Layouts** | `Transfer_Log__c-Transfer Log Layout` |
| **List Views** | `Inventory_Position__c.Inventory_Transfer_Ops` |

### Expected Output

```
Deploying metadata...
[==========] 100% (done)

Component Deletions:
  • CustomObject: Pharmacy_Store__c
  • CustomObject: Medication__c
  • CustomObject: Inventory_Position__c
  • CustomObject: Transfer_Log__c
  • ApexClass: InterStoreTransferAction
  • ApexClass: InterStoreTransferActionTest
  • ApexClass: InterStoreTransferService
  • ApexClass: InterStoreTransferServiceTest
  • ApexClass: InventoryPositionSelector
  • ApexClass: ISTTestDataFactory
  • ApexClass: PostInstallScript
  • Flow: Execute_Inter_Store_Transfer
  • PermissionSet: IST_Ops_User
  • GenAiPromptTemplate: IST_Inventory_Recommendation
  • Layout: Transfer_Log__c-Transfer Log Layout
  • ListView: Inventory_Position__c.Inventory_Transfer_Ops

Deploy Status: Succeeded
```

> **Note:** the current `destructiveChanges.xml` does **not** list `InventoryPositionSelectorTest` or `PostInstallScriptTest` even though they exist in `force-app/`. If those test classes are present in your target org and you want a clean uninstall, delete them manually in Setup or extend the manifest before deploying.

---

## Verification

After completing all three steps, verify the uninstallation:

### 1. Verify Custom Objects Are Removed

```bash
sf sobject describe --sobject Pharmacy_Store__c --target-org <your-org-alias>
```

**Expected Result:** Error message indicating object doesn't exist

### 2. Verify Apex Classes Are Removed

In Setup:
1. Navigate to **Setup > Custom Code > Apex Classes**
2. Search for "InterStoreTransfer"
3. Confirm no classes are found

### 3. Verify Permission Set Is Removed

In Setup:
1. Navigate to **Setup > Users > Permission Sets**
2. Search for "IST_Ops_User"
3. Confirm permission set doesn't exist

### 4. Verify Prompt Template Is Removed

In Setup:
1. Navigate to **App Launcher > Prompt Templates** (or **Setup > Einstein > Prompt Builder**)
2. Search for "IST Inventory Recommendation"
3. Confirm template doesn't exist

> The prompt template was admin-authored, not packaged. The destructive deploy includes it under `GenAiPromptTemplate`, but if the template was never created in this org (e.g. Agentforce was not enabled), the deploy will skip it without failing — there is nothing to remove.

---

## Troubleshooting

### Error: "Cannot delete object with existing records"

**Cause:** Step 1 was skipped or incomplete

**Solution:** 
1. Run the data deletion script again
2. Or manually delete all records from the custom objects

### Error: "Cannot delete permission set with active assignments"

**Cause:** Step 2 was skipped or incomplete

**Solution:**
1. Run the permission set removal script again
2. Or manually remove assignments in Setup > Users > Permission Sets

### Error: "Component is referenced by..."

**Cause:** Another component depends on package metadata

**Solution:**
1. Identify the dependent component in the error message
2. Remove or update the dependent component first
3. Re-run the destructive deployment

### Deployment Fails with Unknown Errors

**Solution:**
1. Check debug logs for detailed error messages
2. Try deleting components individually in Setup UI
3. Contact Salesforce support if issues persist

---

## Rollback / Recovery

If you need to reinstall the package after uninstallation:

1. **Reinstall Package:**
   ```bash
   sf project deploy start --source-dir force-app --target-org <your-org-alias>
   ```

2. **Post-Install Script Will Automatically:**
   - Create sample data (6 stores, 6 medications, 15 inventory positions)
   - Assign the `IST_Ops_User` permission set to the installer
   - **Check** for the `IST_Inventory_Recommendation` prompt template (logs `WARN` if missing — re-author it per [Create the Prompt Template](create-prompt-template.html))

3. **Or Manually Create Data:**
   - Run the demo TC scripts under `scripts/apex/` individually
   - Assign permission sets manually
   - Re-author the prompt template in Prompt Builder

---

## Partial Uninstallation

If you only want to remove sample data but keep the metadata:

### Option 1: Delete Sample Data Only

```bash
# Run only Step 1
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <your-org-alias>
```

### Option 2: Remove Permission Set Assignment Only

```bash
# Run only Step 2
sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <your-org-alias>
```

---

## Clean Up Project Files (Optional)

After successful uninstallation from the org, you can remove the package files from your local project:

```bash
# Remove package source code
rm -rf force-app/main/default/classes/InterStoreTransfer*
rm -rf force-app/main/default/classes/InventoryPositionSelector*
rm -rf force-app/main/default/classes/ISTTestDataFactory*
rm -rf force-app/main/default/classes/PostInstallScript*
rm -rf force-app/main/default/objects/Pharmacy_Store__c
rm -rf force-app/main/default/objects/Medication__c
rm -rf force-app/main/default/objects/Inventory_Position__c
rm -rf force-app/main/default/objects/Transfer_Log__c
rm -rf force-app/main/default/flows/Execute_Inter_Store_Transfer*
rm -rf force-app/main/default/permissionsets/IST_Ops_User*
rm -rf force-app/main/default/layouts/Transfer_Log__c*
# Note: the IST_Inventory_Recommendation prompt template is NOT in force-app/
# — it was admin-authored in Prompt Builder, not packaged as metadata.

# Remove scripts
rm -rf scripts/data
rm -rf scripts/uninstall

# Remove documentation
rm -rf docs
```

---

## Support

If you encounter issues during uninstallation:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review Salesforce debug logs for detailed error messages
3. Test in a sandbox environment first
4. Contact your Salesforce administrator

---

## Related Documentation

- [Deployment Guide](deployment.md)
- [Architecture Overview](../architecture/overview.md)
- [Data Model Reference](../architecture/data-model.md)