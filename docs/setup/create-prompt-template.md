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
- Package deployed with `IST_Inventory_Recommendation` PromptTemplate metadata

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

RULES YOU MUST FOLLOW:
1. If DEA Schedule is "II" output exactly:
  "Schedule II: Manual DEA Form 222 transfer required. No automated action available."

2. If Status is "Critical" (Quantity <= 0) AND DEA Schedule is NOT "II" output:
  "Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action."

3. If Status is "Adequate" AND Quantity is less than double the Safety Stock output:
  "Stock adequate but approaching reorder threshold. Monitor closely."

4. If Status is "Adequate" AND Quantity is greater than or equal to double the Safety Stock output:
  "Stock levels healthy. No action required at this time."

5. If Expiry Date is within 30 days from today prefix your output with:
  "EXPIRY ALERT: [your recommendation]"

6. Never recommend specific transfer quantities in this column.
  Quantities are calculated by the Transfer/Optimize action at execution time.

7. Keep the entire output under 150 characters so it fits cleanly in the Grid column.

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
| Critical stock (Qty=0, non-Schedule II) | `Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action.` |
| Adequate stock, approaching threshold | `Stock adequate but approaching reorder threshold. Monitor closely.` |
| Healthy stock | `Stock levels healthy. No action required at this time.` |
| Expiring soon (within 30 days) | `EXPIRY ALERT: [recommendation text]` |

---

## Verification Checklist

- ✓ Prompt Template name: `IST Inventory Recommendation`
- ✓ API Name: `IST_Inventory_Recommendation`
- ✓ System Prompt contains all seven rules
- ✓ Merge fields reference Inventory_Position__c fields
- ✓ Template is saved and activated
- ✓ Grid displays recommendations under 150 characters
- ✓ DEA compliance rules are enforced
- ✓ No transfer quantities are recommended (per Rule 6)

---

## Troubleshooting

### Template Not Appearing in Grid

- Verify the template is **Active**
- Check that the Agentforce agent is configured to use this template
- Ensure package deployment included the PromptTemplate metadata

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

- [Agentforce Configuration](../architecture/overview.md)
- [Data Model Reference](../architecture/data-model.md)
- [Inventory Position Record](../architecture/data-model.md#inventory_positionc)

