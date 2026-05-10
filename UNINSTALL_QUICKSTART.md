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

**Deletes:** All custom objects, Apex classes, flows, permission sets, and prompt templates

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
| Apex Classes | 7 | InterStoreTransferAction, InterStoreTransferService, PostInstallScript + tests |
| Flows | 1 | Execute_Inter_Store_Transfer |
| Permission Sets | 1 | IST_Ops_User |
| Prompt Templates | 1 | IST_Inventory_Recommendation |
| Layouts | 1 | Transfer Log Layout |
| List Views | 1 | Inventory Transfer Ops |

**Total Records Deleted:** ~29 inventory positions, 6 medications, 6 stores (sample data)

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