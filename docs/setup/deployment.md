---
layout: default
title: Deployment
parent: Setup
nav_order: 1
---

# Deployment Guide

---

## Prerequisites

- **Salesforce CLI** — `sf` (v2+) installed and authenticated
- **Salesforce Org** — Scratch org, sandbox, or production with Agentforce enabled
- **Node.js 18+** — For local development tooling (ESLint, Prettier, Jest)
- **Permissions** — System Administrator profile or equivalent deploy permissions

---

## Option 1: Scratch Org (Development)

```bash
# 1. Clone the repository
git clone https://github.com/jayavardhan-raju/Salesforce-AgentMemory.git
cd Salesforce-AgentMemory

# 2. Create a scratch org (30-day duration)
sf org create scratch \
  -f config/project-scratch-def.json \
  -a IST \
  -d 30

# 3. Push all source
sf project deploy start -o IST

# 4. Assign the permission set
sf org assign permset -n IST_Ops_User -o IST

# 5. Open the org
sf org open -o IST
```

---

## Option 2: Sandbox / Production

```bash
# 1. Authenticate to the target org
sf org login web -a MyOrg

# 2. Deploy using the manifest
sf project deploy start \
  -x manifest/package.xml \
  -o MyOrg

# 3. Assign permission set to relevant users
sf org assign permset -n IST_Ops_User -o MyOrg
```

---

## Post-Deployment: Load Test Data

Three Anonymous Apex scripts must be executed **in order** to set up the test scenarios. Run these in Developer Console → Debug → Open Execute Anonymous Window.

### Script 1: Stores + Medications

Creates 3 pharmacy stores (CVS Downtown, CVS Westside, Walgreens North) and 3 medications (Mounjaro, Adderall, Mounjaro 5mg).

```bash
sf apex run -f scripts/IST_Script1_Stores_Meds.apex -o IST
```

### Script 2: Inventory Positions

Creates 7 inventory position records across the 3 test case scenarios. Uses idempotent upsert logic with `String.valueOf(Id)` keys to avoid Apex arithmetic errors on Id concatenation.

```bash
sf apex run -f scripts/IST_Script2_Inventory.apex -o IST
```

### Script 3: Verify + Print Test Case IDs

Verifies all data and prints the test case IDs needed for Agentforce Grid testing.

```bash
sf apex run -f scripts/IST_Script3_Verify.apex -o IST
```

Expected output:

```
TC1 HAPPY PATH  | IP-0001 | a0XXXXXXXXXX
TC2 SCHEDULE II | IP-0002 | a0XXXXXXXXXX
TC3 NO SOURCE   | IP-0003 | a0XXXXXXXXXX
```

### Test Case Data Map

| Row | Store | Medication | Qty | Safety | Expiry | Role |
|-----|-------|-----------|-----|--------|--------|------|
| 1 | CVS Downtown | Mounjaro | 0 | 50 | +70d | TC1 TARGET (Critical) |
| 2 | CVS Westside | Mounjaro | 200 | 50 | +42d | TC1 ELIGIBLE SOURCE |
| 3 | Walgreens North | Mounjaro | 250 | 50 | +50d | TC1 ELIGIBLE SOURCE (selected first — highest qty) |
| 4 | CVS Downtown | Adderall | 0 | 30 | +90d | TC2 TARGET (Schedule II block) |
| 5 | CVS Downtown | Mounjaro 5mg | 0 | 60 | +70d | TC3 TARGET (no eligible source) |
| 6 | CVS Westside | Mounjaro 5mg | 70 | 65 | +20d | TC3 EXCLUDED (20d < 30d expiry threshold) |
| 7 | Walgreens North | Mounjaro 5mg | 300 | 50 | +15d | TC3 EXCLUDED (15d < 30d expiry threshold) |

---

## Post-Deployment: Configure Agentforce

These steps are performed in the Salesforce UI after metadata deployment:

### 1. Create the Prompt Template

Navigate to Setup → Einstein → Prompt Builder. Create a new prompt template named **IST Inventory Recommendation** using the template code documented in the [Agentforce Configuration](../agentforce/configuration.md) page.

### 2. Deploy the Agent Script

Navigate to Setup → Agentforce → Agent Builder. Create the **inventory_transfer_ops_agent** agent using the script documented in the [Agentforce Configuration](../agentforce/configuration.md) page.

### 3. Configure the Grid

1. Navigate to the `Inventory_Position__c` tab
2. Select the **Inventory Transfer Ops** list view
3. Enable the Agentforce Grid with the `inventory_transfer_ops_agent`
4. Add **Transfer/Optimize** as a row action wired to the `Execute_Inter_Store_Transfer` flow

### 4. Assign Permission Set

Ensure all operations users have the `IST_Ops_User` permission set:

```bash
sf org assign permset \
  -n IST_Ops_User \
  -o MyOrg \
  -b "user@example.com"
```

---

## Uninstallation

1. Remove Agentforce Grid configuration from `Inventory_Position__c`
2. Deactivate the `Execute_Inter_Store_Transfer` flow
3. Delete all `Transfer_Log__c`, `Inventory_Position__c`, `Medication__c`, and `Pharmacy_Store__c` records
4. Remove metadata via destructive changes or manual deletion
5. Remove the `IST_Ops_User` permission set assignments
