---
layout: default
title: Deployment Guide
parent: Setup
nav_order: 1
---

# Deployment Guide

Step-by-step instructions for deploying AgentforceGrid to a Salesforce org.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Salesforce Org** | Must have Agentforce enabled with API version 65.0 or higher |
| **Salesforce CLI** | `sf` CLI installed ([Install Guide](https://developer.salesforce.com/tools/salesforcecli)) |
| **Dev Hub** | Required for scratch org deployments. Enable in Setup → Dev Hub |
| **Source Tracking** | The project uses SFDX source format (`force-app/main/default/`) |

---

## Deploy to a Scratch Org

```bash
# 1. Clone the repository
git clone https://github.com/jayavardhan-raju/AgentforceGrid.git
cd AgentforceGrid

# 2. Create a scratch org (requires Dev Hub authorization)
sf org create scratch \
  -f config/project-scratch-def.json \
  -a AgentforceGrid \
  -d 30

# 3. Deploy all metadata
sf project deploy start -o AgentforceGrid

# 4. Assign the permission set to the default user
sf org assign permset -n IST_Ops_User -o AgentforceGrid

# 5. Open the org
sf org open -o AgentforceGrid
```

---

## Deploy to a Sandbox or Production

```bash
# 1. Authenticate to your target org
sf org login web -a MyTargetOrg

# 2. Deploy the source
sf project deploy start \
  --target-org MyTargetOrg \
  --source-dir force-app

# 3. Assign the permission set to operations users
sf org assign permset \
  -n IST_Ops_User \
  -o MyTargetOrg

# 4. (Optional) Validate without deploying — check-only deployment
sf project deploy start \
  --target-org MyTargetOrg \
  --source-dir force-app \
  --dry-run \
  --test-level RunLocalTests
```

---

## Post-Deployment Configuration

After deploying the metadata, the following manual steps are required:

### 1. Verify Permission Set Assignment

Assign `IST_Ops_User` to all users who will operate the Agentforce Grid. This permission set grants:

| Object | Create | Read | Edit | Delete |
|--------|--------|------|------|--------|
| `Inventory_Position__c` | Yes | Yes | Yes | Yes |
| `Medication__c` | Yes | Yes | Yes | Yes |
| `Pharmacy_Store__c` | Yes | Yes | Yes | Yes |
| `Transfer_Log__c` | Yes | Yes | No | No |

Note: `Transfer_Log__c` is intentionally restricted to Create + Read only to preserve audit trail immutability.

### 2. Activate the Flow

1. Navigate to **Setup → Flows**
2. Find `Execute Inter Store Transfer`
3. Verify its status is **Active**
4. If not active, open the flow and click **Activate**

### 3. Configure the Agentforce Grid

1. Navigate to the `Inventory_Position__c` tab
2. Set up an Agentforce Grid component on the page
3. Configure it to use the `Inventory Transfer Ops` list view
4. Map the Grid action button to the `Execute Inter-Store Transfer` invocable action
5. Ensure the Grid columns include `Recommendation_Preview__c` for transfer status visibility

### 4. Load Sample Data (3 Apex Scripts)

The project includes 3 Apex anonymous scripts that load a complete demo dataset. **Run them in order** — each script depends on the records created by the previous one.

```bash
# Script 1: Create 6 Pharmacy Stores (2 districts, varied capabilities)
sf apex run --file scripts/data/1_Create_Pharmacy_Stores.apex --target-org <your-org-alias>

# Script 2: Create 6 Medications (Schedule II, cold-chain, standard)
sf apex run --file scripts/data/2_Create_Medications.apex --target-org <your-org-alias>

# Script 3: Create 16 Inventory Positions (6 demo scenarios)
sf apex run --file scripts/data/3_Create_Inventory_Positions.apex --target-org <your-org-alias>
```

#### What the scripts create

**Script 1 — Pharmacy Stores** creates 6 stores across 2 districts with varied configurations to exercise all source selection filter paths:

| Store | District | Cold Chain | DEA Reg | Active | Purpose |
|-------|----------|-----------|---------|--------|---------|
| CVS Downtown SF | District 1 - Bay Area | Yes | Yes | Yes | Primary target store for demo scenarios |
| CVS Westside SF | District 1 - Bay Area | Yes | Yes | Yes | Primary source store (cold-chain capable) |
| CVS Eastside Oakland | District 1 - Bay Area | No | Yes | Yes | Filtered out for cold-chain medications |
| CVS San Jose Central | District 2 - South Bay | Yes | Yes | Yes | Source for Schedule IV and multi-source demos |
| CVS Sunnyvale | District 2 - South Bay | Yes | No | Yes | No DEA registration — filtered out as source |
| CVS Palo Alto (Closed) | District 2 - South Bay | Yes | Yes | No | Inactive — excluded by SOQL WHERE clause |

**Script 2 — Medications** creates 6 medications covering all DEA schedules and handling requirements:

| Medication | DEA Schedule | Cold Chain | Purpose |
|-----------|-------------|-----------|---------|
| Mounjaro 5mg | None | Yes | Happy path with cold-chain validation |
| Ozempic 1mg | None | Yes | Near-expiry source exclusion scenario |
| Adderall XR 30mg | II | No | Schedule II compliance hard stop |
| Xanax 0.5mg | IV | No | Allowed controlled substance transfer |
| Lisinopril 10mg | None | No | No suitable source (distributor fallback) |
| Amoxicillin 500mg | None | No | Multiple eligible sources scenario |

**Script 3 — Inventory Positions** creates 16 positions across 6 demo scenarios:

| # | Scenario | Target Store (Trigger Row) | Expected Outcome |
|---|----------|--------------------------|------------------|
| 1 | **Happy Path** | CVS Downtown SF — Mounjaro 5mg (Qty: 0) | Transfer from CVS Westside SF; CVS Eastside Oakland filtered out (no cold chain) |
| 2 | **Schedule II Block** | CVS Downtown SF — Adderall XR 30mg (Qty: 5) | Hard compliance stop, `Transfer_Log__c` with `Blocked` status |
| 3 | **No Source Fallback** | CVS Downtown SF — Lisinopril 10mg (Qty: 0) | Distributor order recommendation (no store has surplus) |
| 4 | **Expiry Exclusion** | CVS San Jose Central — Ozempic 1mg (Qty: 5) | CVS Downtown SF excluded (15-day expiry); CVS Westside SF selected (120-day expiry) |
| 5 | **Schedule IV Allowed** | CVS Eastside Oakland — Xanax 0.5mg (Qty: 10) | Transfer from CVS San Jose Central (Schedule IV is not blocked) |
| 6 | **Multiple Sources** | CVS Sunnyvale — Amoxicillin 500mg (Qty: 0) | CVS Downtown SF selected (300 units > 120 units at CVS San Jose Central) |

#### Customizing for production

The scripts above load demo data. For production deployments, replace the script contents with your actual store, medication, and inventory data, or load data via Data Loader / Data Import Wizard. The key requirements are:

- Every `Pharmacy_Store__c` must have `Is_Active__c = true` and a non-blank `DEA_Registration__c` to be eligible as a transfer source
- Every `Medication__c` must have a unique `NDC__c` value
- `Inventory_Position__c` records need both `Quantity__c` and `Safety_Stock__c` populated for the status formula to compute correctly

### 5. Verify the Workflow

Test the end-to-end workflow using the demo data:

1. Open the Agentforce Grid on the `Inventory_Position__c` object with the `Inventory Transfer Ops` list view
2. Find the **Mounjaro 5mg at CVS Downtown SF** row (Qty: 0, Status: OUT_OF_STOCK)
3. Click the Transfer/Optimize action button on that row
4. Verify the dry-run recommendation appears — it should recommend CVS Westside SF as the source
5. Confirm the transfer via the agent conversation
6. Verify a `Transfer_Log__c` record was created with `Transfer_Status__c = 'Completed'`
7. Verify the source and target inventory quantities were updated
8. Test the **Adderall XR 30mg** row to verify the Schedule II compliance block
9. Test the **Lisinopril 10mg** row to verify the distributor fallback message
