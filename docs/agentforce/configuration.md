---
layout: default
title: Agentforce Configuration
parent: Agentforce
nav_order: 1
---

# Agentforce Configuration

This page documents the manual configuration steps required after deploying the force-app metadata. These components are configured through the Salesforce UI, not deployed as metadata.

---

## 1. Prompt Template: IST Inventory Recommendation

Create this prompt template in Setup → Einstein → Prompt Builder.

**Template Name:** IST Inventory Recommendation

**Purpose:** Generates concise, rule-based inventory status recommendations that appear in the Agentforce Grid column. The output is capped at 150 characters to fit cleanly in the Grid.

**Data Action:** Uses `$SalesforceDataAction:getInventorySummaryData.inventoryData` to pull inventory context.

**Merge Fields:**

| Merge Field | Description |
|-------------|-------------|
| `{!$Input:Inventory_Position__c.Id}` | Record ID |
| `{!$Input:Inventory_Position__c.Store__r.Name}` | Store name |
| `{!$Input:Inventory_Position__c.Medication__r.Name}` | Medication name |
| `{!$Input:Inventory_Position__c.Medication__r.DEA_Schedule__c}` | DEA Schedule |
| `{!$Input:Inventory_Position__c.Medication__r.Cold_Chain_Required__c}` | Cold chain flag |
| `{!$Input:Inventory_Position__c.Quantity__c}` | Current quantity |
| `{!$Input:Inventory_Position__c.Safety_Stock__c}` | Safety stock level |
| `{!$Input:Inventory_Position__c.Expiry_Date__c}` | Expiry date |
| `{!$Input:Inventory_Position__c.Status__c}` | Computed status |

**Output Rules:**

| # | Condition | Output |
|---|-----------|--------|
| 1 | DEA Schedule = "II" | "Schedule II: Manual DEA Form 222 transfer required. No automated action available." |
| 2 | Status = "Critical" (Qty ≤ 0) AND not Schedule II | "Critical stock. Recommend initiating inter-store transfer via Transfer/Optimize action." |
| 3 | Status = "Adequate" AND Qty < 2× Safety Stock | "Stock adequate but approaching reorder threshold. Monitor closely." |
| 4 | Status = "Adequate" AND Qty ≥ 2× Safety Stock | "Stock levels healthy. No action required at this time." |
| 5 | Expiry within 30 days | Prefix output with "EXPIRY ALERT: " |
| 6 | Always | Never recommend specific transfer quantities |
| 7 | Always | Keep entire output under 150 characters |

**Output Format:** Plain text only. No preamble, no explanation, no JSON, no labels.

---

## 2. Agent Script: inventory_transfer_ops_agent

Create this agent in Setup → Agentforce → Agent Builder.

**Developer Name:** `inventory_transfer_ops_agent`
**Description:** Manages inter-store inventory transfers via Agentforce Grid. Enforces DEA compliance and two-step execution.
**Default Agent User:** `inventorytransferops@[your-org-id].ext`
**Welcome Message:** "Inventory Transfer Operations Agent ready. Select a Critical Stock row and click Transfer/Optimize to begin."

### Agent Variables

| Variable | Type | Mutable | Description |
|----------|------|---------|-------------|
| `inventory_position_id` | String | Yes | Salesforce ID of the `Inventory_Position__c` record being evaluated |
| `dry_run_success` | Boolean | Yes | True if the dry-run recommendation succeeded |
| `recommended_qty` | Number | Yes | Quantity recommended for transfer from the dry-run |
| `source_store_name` | String | Yes | Name of the recommended source store |
| `uh_text` | String | Yes | Last `uhText` returned from the action — shown to the user |
| `confirmed` | Boolean | Yes | True once the user has explicitly confirmed they want to proceed |

### Agent Behavior Rules

The agent script enforces these critical behaviors:

1. **Never execute without explicit confirmation** — The agent must receive "yes", "proceed", or "confirm" before setting `confirmed=true`
2. **Never bypass Schedule II restrictions** — These are non-negotiable compliance requirements
3. **Always surface uhText verbatim** — Do not paraphrase compliance block messages
4. **Never offer "Shall I proceed?" when success=false** — The `uhText` already contains the next action for the user
5. **Never auto-escalate to a human** — Unless the user explicitly requests it

### Two-Step Workflow

**Step 1 — Dry Run:**
If `inventory_position_id` is set AND `dry_run_success=false` AND `confirmed=false`:
- Call `Execute_Inter_Store_Transfer` with `confirm=false`
- Store outputs in agent variables
- Display `uh_text` to user exactly as returned

**Step 2 — Compliance/Fallback Gate:**
If `dry_run_success=false`:
- Do NOT ask "Shall I proceed?"
- Stop here. The `uhText` already contains the user's next action.

**Step 3 — Confirmation Prompt:**
If `dry_run_success=true` AND `confirmed=false`:
- Ask: "Shall I proceed with this transfer?"
- Only set `confirmed=true` when user explicitly confirms

**Step 4 — Execution:**
If `confirmed=true`:
- Call `Execute_Inter_Store_Transfer` with `confirm=true`
- Display `uh_text` to user

### Agent Actions

| Action | Target | Description |
|--------|--------|-------------|
| `evaluate_transfer` | `flow://Execute_Inter_Store_Transfer` | Dry-run evaluation. Available when `inventory_position_id` is set. |
| `execute_transfer` | `flow://Execute_Inter_Store_Transfer` | Atomic execution. Available when `confirmed=true`. |
| `Execute_Inter_Store_Transfer` | `apex://InterStoreTransferAction` | Direct Apex invocation. Requires user confirmation. |

### Action I/O Mapping

**Inputs:**

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| `inventoryPositionId` | Id | Yes | Target `Inventory_Position__c` record ID |
| `confirm` | Boolean | No | `false` = dry-run, `true` = execute |

**Outputs:**

| Output | Type | Description |
|--------|------|-------------|
| `success` | Boolean | Whether the operation succeeded |
| `uhText` | String | Human-readable message for agent to surface |
| `sourceStoreId` | Id | Recommended source store ID |
| `sourceStoreName` | String | Recommended source store name |
| `recommendedQty` | Integer | Units recommended for transfer |
| `transferLogId` | Id | Transfer log ID (null on dry-run) |

---

## 3. Grid Configuration

After deploying the metadata and creating the agent:

1. Navigate to the `Inventory_Position__c` tab
2. Select the **Inventory Transfer Ops** list view
3. Configure the Agentforce Grid to use the `inventory_transfer_ops_agent`
4. Add **Transfer/Optimize** as a row action wired to `Execute_Inter_Store_Transfer` flow
5. Ensure the `Recommendation_Preview__c` column is visible in the Grid
