# 🗑️ Quick Uninstall Guide

**Complete package removal in 3 steps.**

## ⚠️ Warning

This will **permanently delete ALL package data and metadata**. Back up any data you want to keep first!

---

## 3-Step Uninstallation

### Step 1: Delete Sample Data (1 min)

```bash
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <your-org-alias>
```

**Deletes:** All Pharmacy Stores, Medications, Inventory Positions, Transfer Logs

---

### Step 2: Remove Permission Sets (1 min)

```bash
sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <your-org-alias>
```

**Removes:** IST_Ops_User permission set assignments from all users

---

### Step 3: Deploy Destructive Changes (2-3 min)

```bash
sf project deploy start \
  --manifest manifest/destructiveChanges.xml \
  --post-destructive-changes manifest/destructivePackage.xml \
  --target-org <your-org-alias>
```

**Deletes:** All custom objects, Apex classes (production + test), flows, permission sets, and the admin-authored `IST_Inventory_Recommendation` `GenAiPromptTemplate` (if present in the org)

---

## One-Line Uninstall (All Steps)

```bash
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <alias> && \
sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <alias> && \
sf project deploy start --manifest manifest/destructiveChanges.xml --post-destructive-changes manifest/destructivePackage.xml --target-org <alias>
```

**Note:** Replace `<alias>` with your org alias

---

## What Gets Removed

| Component Type | Count | Examples |
|---------------|-------|----------|
| Custom Objects | 4 | Pharmacy_Store__c, Medication__c, Inventory_Position__c, Transfer_Log__c |
| Apex Classes | 9 | InterStoreTransferAction(+Test), InterStoreTransferService(+Test), InventoryPositionSelector(+Test), PostInstallScript(+Test), ISTTestDataFactory |
| Flows | 1 | Execute_Inter_Store_Transfer |
| Permission Sets | 1 | IST_Ops_User |
| Gen AI Prompt Templates | 1 | IST_Inventory_Recommendation (admin-authored; only removed if it exists in the org) |
| Layouts | 1 | Transfer Log Layout |
| List Views | 1 | Inventory Transfer Ops |

> Note: the destructiveChanges manifest currently lists `InterStoreTransferActionTest` and `InterStoreTransferServiceTest` but **not** `InventoryPositionSelectorTest` or `PostInstallScriptTest`. If those exist in your org and you want a clean uninstall, remove them manually or extend the manifest.

**Total Records Deleted:** 14 inventory positions, 6 medications, 6 stores (sample data created by PostInstallScript)

---

## Verification Commands

```bash
# Check if objects are removed
sf sobject describe --sobject Pharmacy_Store__c --target-org <alias>

# Expected: ERROR running sobject describe: The requested resource does not exist
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| "Cannot delete object with existing records" | Run Step 1 again |
| "Cannot delete permission set with active assignments" | Run Step 2 again |
| "Component is referenced by..." | Remove dependent component first |

---

## Partial Uninstall Options

### Delete Data Only (Keep Metadata)

```bash
sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <alias>
```

### Remove Permission Set Only

```bash
sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <alias>
```

---

## Rollback / Reinstall

To reinstall after uninstallation:

```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

Post-install script will automatically recreate sample data and assign permissions.

---

## Full Documentation

For detailed troubleshooting, recovery options, and step-by-step explanations, see:

📖 **[Complete Uninstall Guide](docs/setup/uninstall.md)**

---

## Support

- 📋 Review [Troubleshooting](docs/setup/uninstall.md#troubleshooting)
- 🔍 Check Salesforce debug logs
- 🧪 Test in sandbox first
- 👥 Contact your Salesforce administrator

---

**Estimated Total Time:** 5-10 minutes

**Prerequisites:** Salesforce CLI, System Administrator permissions