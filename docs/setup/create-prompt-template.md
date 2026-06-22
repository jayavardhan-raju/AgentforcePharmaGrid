---
layout: default
title: Create IST Inventory Recommendation Prompt Template
parent: Setup
nav_order: 3
---

# Creating the IST Inventory Recommendation Prompt Template

This guide walks through manual creation of the **IST Inventory Recommendation** prompt template in Salesforce Agentforce.

## Prerequisites

- Salesforce org with Agentforce enabled
- System Administrator or equivalent permissions
- AgentforcePharmaGrid package deployed (the prompt template itself is NOT
  shipped as metadata — Salesforce's `GenAiPromptTemplate` metadata requires
  server-generated hash identifiers that can't be hand-authored, so the steps
  below are the supported way to create it)

---

## Step-by-Step Instructions

### Step 1: Navigate to Prompt Templates

1. In Salesforce, click the **App Launcher** (grid icon) in the top-left corner
2. Search for **"Prompt Templates"** and select it from the results
3. You should see the **Prompt Templates** list view

### Step 2: Create a New Prompt Template

1. Click the **New** button (top-right corner)
2. A new Prompt Template form will open

### Step 3: Fill in Basic Information

| Field | Value |
|-------|-------|
| **Name** | `IST Inventory Recommendation` |
| **API Name** | `IST_Inventory_Recommendation` (auto-populated) |
| **Description** | `Analyzes inventory records and generates actionable recommendations following DEA compliance and stock level rules.` |

### Step 4: Configure System Prompt

1. In the **System Prompt** field, paste the following text exactly as shown:

```
You are a US retail pharmacy inventory analyst assistant.
Analyse the inventory record below and generate a concise, actionable
recommendation in 1-2 sentences maximum.

INVENTORY RECORD:
- Record ID: {!$Input:Inventory_Position__c.Id}
- Store: {!$Input:Inventory_Position__c.Store__r.Name}
- Medication: {!$Input:Inventory_Position__c.Medication__r.Name}
- DEA Schedule: {!$Input:Inventory_Position__c.Medication__r.DEA_Schedule__c}
- Cold Chain Required: {!$Input:Inventory_Position__c.Medication__r.Cold_Chain_Required__c}
- Current Quantity: {!$Input:Inventory_Position__c.Quantity__c}
- Safety Stock Level: {!$Input:Inventory_Position__c.Safety_Stock__c}
- Expiry Date: {!$Input:Inventory_Position__c.Expiry_Date__c}
- Status: {!$Input:Inventory_Position__c.Status__c}

RULES YOU MUST FOLLOW (apply in this exact order — stop at the first match):

1. DEA SCHEDULE OVERRIDE
   If DEA Schedule equals "II", output exactly:
   "Schedule II: Manual DEA Form 222 transfer required. No automated action available."
   (This rule overrides all others — do not evaluate any rule below.)

2. STATUS DISPATCH
   Output text is determined by the Status value:
   - Status = "OUT_OF_STOCK" → output:
     "Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action."
   - Status = "LOW" → output:
     "Stock below safety threshold. Recommend initiating inter-store transfer via Transfer/Optimize action."
   - Status = "HEALTHY" AND Quantity is less than double the Safety Stock → output:
     "Stock adequate but approaching reorder threshold. Monitor closely."
   - Status = "HEALTHY" AND Quantity is greater than or equal to double the Safety Stock → output:
     "Stock levels healthy. No action required at this time."
   - Status = "UNKNOWN" → output:
     "Safety stock not configured. Set Safety_Stock__c to enable recommendations."

3. EXPIRY ALERT PREFIX
   If Expiry Date is within 30 days from today, prefix the rule 1 or rule 2 output with:
   "EXPIRY ALERT: "

4. CONSTRAINTS
   - Never recommend specific transfer quantities (those are calculated by the Transfer/Optimize action at execution time).
   - Keep total output under 150 characters.

OUTPUT ONLY THE RECOMMENDATION TEXT.
No preamble. No explanation. No JSON. No labels. Just the recommendation sentence.
```

### Step 5: Define Input Variables

The System Prompt uses merge fields that reference `Inventory_Position__c` record data. These are automatically resolved by the Agentforce context.

**Input fields referenced:**
- `Inventory_Position__c.Id` — Record ID
- `Inventory_Position__c.Store__r.Name` — Pharmacy Store name
- `Inventory_Position__c.Medication__r.Name` — Medication name
- `Inventory_Position__c.Medication__r.DEA_Schedule__c` — DEA Schedule (II, III, IV, V, None)
- `Inventory_Position__c.Medication__r.Cold_Chain_Required__c` — Cold chain requirement
- `Inventory_Position__c.Quantity__c` — Current quantity on hand
- `Inventory_Position__c.Safety_Stock__c` — Safety stock threshold
- `Inventory_Position__c.Expiry_Date__c` — Medication expiry date
- `Inventory_Position__c.Status__c` — Computed status (OUT_OF_STOCK, LOW, HEALTHY, UNKNOWN)

### Step 6: Save the Prompt Template

1. Click **Save** at the bottom of the form
2. The system will validate the template and generate the API name `IST_Inventory_Recommendation`
3. You should see a confirmation message: "Prompt Template created successfully"

---

## Step 7: Activate the Template (Optional)

1. After saving, open the template again
2. If there is an **"Activate"** button, click it to make the template available for use in Agentforce agents
3. Mark as **"Active"** in the status field if applicable

---

## Testing the Template

### Test with Sample Data

Once created, test the prompt template with the Agentforce Grid:

1. Navigate to **Agentforce Grid** for Inventory Positions
2. Select an inventory record
3. The grid should call this prompt template to generate recommendations
4. Verify recommendations follow the rules:
   - Schedule II medications show the exact compliance message
   - Critical stock shows transfer recommendation
   - Adequate stock shows monitoring guidance
   - Expiry alerts are prefixed when within 30 days

### Expected Output Examples

| Scenario | Expected Output |
|----------|---|
| Schedule II medication | `Schedule II: Manual DEA Form 222 transfer required. No automated action available.` |
| Status = OUT_OF_STOCK (non-Schedule II) | `Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action.` |
| Status = LOW (non-Schedule II) | `Stock below safety threshold. Recommend initiating inter-store transfer via Transfer/Optimize action.` |
| Status = HEALTHY, Qty < 2× Safety Stock | `Stock adequate but approaching reorder threshold. Monitor closely.` |
| Status = HEALTHY, Qty ≥ 2× Safety Stock | `Stock levels healthy. No action required at this time.` |
| Status = UNKNOWN | `Safety stock not configured. Set Safety_Stock__c to enable recommendations.` |
| Expiring soon (within 30 days) | `EXPIRY ALERT: <recommendation text>` |

---

## Verification Checklist

- ✓ Prompt Template name: `IST Inventory Recommendation`
- ✓ API Name: `IST_Inventory_Recommendation`
- ✓ System Prompt contains all four ordered rule groups
- ✓ Merge fields reference Inventory_Position__c fields
- ✓ Template is saved and activated
- ✓ Grid displays recommendations under 150 characters
- ✓ DEA compliance rules are enforced
- ✓ No transfer quantities are recommended (per Rule 4 — Constraints)

---

## Troubleshooting

### Template Not Appearing in Grid

- Verify the template is **Active** (`ActiveVersion = 1` in the `AiPrompt` row)
- Check that the Agentforce Grid component is configured to use `IST_Inventory_Recommendation` as the Recommendation column source
- Run `SELECT DeveloperName, ActiveVersion FROM AiPrompt WHERE DeveloperName = 'IST_Inventory_Recommendation'` to confirm the template exists
- Remember: the template is **not** in `force-app/` — re-running `sf project deploy` will not create it

### Merge Fields Not Resolving

- Confirm the Inventory_Position__c record has related Store and Medication records
- Check that USER_MODE is enforced (field-level security)
- Verify the agent has read access to all referenced fields

### Recommendations Exceeding 150 Characters

- Prompt template may need rule refinement
- Use LLM parameter adjustment (temperature, max_tokens) if available
- Trim recommendation text to fit column width

---

## Related Documentation

- [Agentforce Grid Integration](../api-reference/agentforce-grid.html) — how the Grid binds this template to the Recommendation column
- [Architecture Overview](../architecture/overview.html) — where the prompt template sits in the layered architecture
- [Data Model Reference](../architecture/data-model.html) — the `Inventory_Position__c` fields the system prompt merges
- [Deployment Guide](deployment.html) — runs `PostInstallScript.verifyPromptTemplate()` after deploy and logs a `WARN` until this template exists

