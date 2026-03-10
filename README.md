# Pharmacy Inter-Store Transfer (IST) — Agentforce Grid

**An Agentforce-powered inter-store inventory transfer system for US retail pharmacy, built on native Apex with DEA Schedule II compliance, cold-chain validation, expiry filtering, and atomic two-step execution — all orchestrated through an Agentforce Grid agent.**

---

## Overview

Pharmacy IST solves a critical problem in retail pharmacy operations: when a store runs out of a medication, operations staff need to quickly identify a nearby store with surplus stock and initiate a transfer — while strictly complying with DEA controlled substance regulations, cold-chain handling requirements, and stock expiry rules.

This project provides an end-to-end solution built entirely on the Salesforce platform. An **Agentforce Grid agent** sits on top of the `Inventory_Position__c` list view. When an operator clicks "Transfer/Optimize" on a critical stock row, the agent orchestrates a two-step workflow: first a dry-run recommendation (showing the best source store, quantity, and compliance checks), then — only after explicit user confirmation — an atomic execution that moves inventory, updates both stores, and writes an immutable audit trail.

The system **never** allows automated transfers of DEA Schedule II controlled substances (e.g., Adderall, OxyContin). These are hard-blocked before any source search occurs, and the block is logged for DEA audit compliance.

### Key Capabilities

- **DEA Schedule II Hard Block** — Compliance gate fires before any source search. No automated transfer, no confirmation prompt. `Transfer_Log__c` with status `Blocked` is written for DEA audit trail.
- **Cold-Chain Validation** — Source stores are only eligible if they have cold-chain capability matching the medication's requirement.
- **Expiry Threshold Filtering** — Source stock expiring within 30 days (`MIN_DAYS_TO_EXPIRY`) is automatically excluded from transfer candidates.
- **Two-Step Execution** — Dry-run (recommend) → User confirmation → Atomic execute. The agent never auto-executes.
- **Atomic DML with Savepoint** — Inventory deductions, additions, and audit logs are wrapped in a `Database.setSavepoint()` with full rollback on any failure.
- **Agentforce Grid Integration** — Invocable Action wired to an Auto-Launched Flow, surfaced as a Grid row action. Agent script enforces the two-step workflow.
- **Einstein Prompt Template** — `IST Inventory Recommendation` provides AI-generated inventory status summaries directly in the Grid column.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    AGENTFORCE LAYER                           │
│  ┌────────────────────────┐  ┌────────────────────────────┐  │
│  │ Agent Script            │  │ Prompt Template            │  │
│  │ inventory_transfer_ops  │  │ IST Inventory              │  │
│  │ _agent                  │  │ Recommendation             │  │
│  └───────────┬────────────┘  └────────────────────────────┘  │
│              │                                               │
├──────────────┼───────────────────────────────────────────────┤
│              ▼           FLOW LAYER                           │
│  ┌─────────────────────────────────────────────────────┐     │
│  │   Execute_Inter_Store_Transfer (Auto-Launched Flow)  │     │
│  │   Inputs: inventoryPositionId, confirm               │     │
│  │   Invokes: InterStoreTransferAction (Apex)           │     │
│  └──────────────────────┬──────────────────────────────┘     │
│                         │                                    │
├─────────────────────────┼────────────────────────────────────┤
│                         ▼        INVOCABLE ACTION            │
│  ┌───────────────────────────────────────────────────┐       │
│  │          InterStoreTransferAction                 │       │
│  │   @InvocableMethod — ActionInput / ActionOutput   │       │
│  │   Delegates all logic to Service layer            │       │
│  └──────────────────────┬────────────────────────────┘       │
│                         │                                    │
├─────────────────────────┼────────────────────────────────────┤
│                         ▼          SERVICE                   │
│  ┌───────────────────────────────────────────────────┐       │
│  │         InterStoreTransferService                 │       │
│  │   evaluate()  — Entry point                       │       │
│  │   isScheduleII()  selectBestSource()              │       │
│  │   calculateTransferQty()  buildRecommendation()   │       │
│  │   executeTransfer()  logComplianceBlock()         │       │
│  └───┬───────────────────────────────────────────────┘       │
│      │                                                       │
│      ▼                                                       │
│  ┌────────────────────────────────────────────────────┐      │
│  │          InventoryPositionSelector                 │      │
│  │   getById()  findSurplusSources()                  │      │
│  │   ALL SOQL — zero DML, zero business logic         │      │
│  └────────────────────────────────────────────────────┘      │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                       DATA MODEL                             │
│  Pharmacy_Store__c ─┐                                        │
│  Medication__c ─────┤── Inventory_Position__c                │
│                     └──< Transfer_Log__c (audit trail)       │
└──────────────────────────────────────────────────────────────┘
```

The project follows a strict **Action → Service → Selector** pattern:

| Layer | Class | Responsibility |
|-------|-------|----------------|
| **Invocable Action** | `InterStoreTransferAction` | `@InvocableMethod` entry point — wires Agentforce inputs/outputs to Service |
| **Service** | `InterStoreTransferService` | All business logic: compliance, eligibility, quantity calc, atomic DML |
| **Selector** | `InventoryPositionSelector` | All SOQL — `getById()`, `findSurplusSources()` — zero DML |
| **Flow** | `Execute_Inter_Store_Transfer` | Auto-Launched Flow bridging Agentforce agent to Apex Invocable |
| **Test Factory** | `ISTTestDataFactory` | Shared test data builder for stores, medications, inventory |

---

## Data Model

### Pharmacy_Store__c

Represents a physical pharmacy location in the distribution network.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | Text | Store name (e.g., "CVS Downtown") |
| `District__c` | Text(80) | Operational district for routing |
| `Latitude__c` | Number(9,6) | GPS latitude |
| `Longitude__c` | Number(9,6) | GPS longitude |
| `Cold_Chain_Capable__c` | Checkbox | Whether the store can handle cold-chain medications |
| `DEA_Registration__c` | Text(50) | DEA registration identifier for controlled substances |
| `Is_Active__c` | Checkbox, default true | Whether the store is active for operations |

### Medication__c

Master medication record with regulatory classification.

| Field | Type | Description |
|-------|------|-------------|
| `Name` | Text | Medication name |
| `NDC__c` | Text(30), Unique, Required | National Drug Code — unique identifier |
| `DEA_Schedule__c` | Picklist (restricted) | II, III, IV, V, or None (default) |
| `Cold_Chain_Required__c` | Checkbox | Whether the medication requires cold-chain handling |

### Inventory_Position__c

Per-store, per-medication inventory snapshot — the primary Grid record.

| Field | Type | Description |
|-------|------|-------------|
| `Store__c` | Lookup(Pharmacy_Store__c), Required | Parent pharmacy store |
| `Medication__c` | Lookup(Medication__c), Required | Parent medication |
| `Quantity__c` | Number(18,0), Required | On-hand quantity |
| `Safety_Stock__c` | Number(18,0) | Replenishment threshold |
| `Expiry_Date__c` | Date | Current lot expiry date |
| `Status__c` | Formula(Text) | OUT_OF_STOCK / LOW / HEALTHY / UNKNOWN |
| `Status_Color__c` | Formula(Text) | RED / ORANGE / GREEN / GRAY for UI |
| `Recommendation__c` | Long Text (32KB) | Full recommendation text for record detail |
| `Recommendation_Preview__c` | Text(255) | Truncated preview for Agentforce Grid column |
| `Store_Name__c` | Formula(Text) | `Store__r.Name` |
| `Medication_Name__c` | Formula(Text) | `Medication__r.Name` |

**Status Formula:**
```
IF(ISBLANK(Safety_Stock__c), "UNKNOWN",
  IF(Quantity__c <= 0, "OUT_OF_STOCK",
    IF(Quantity__c < Safety_Stock__c, "LOW", "HEALTHY")))
```

### Transfer_Log__c

Immutable audit trail for every transfer attempt — successful, blocked, or failed.

| Field | Type | Description |
|-------|------|-------------|
| `Source_Store__c` | Lookup(Pharmacy_Store__c) | Source pharmacy |
| `Target_Store__c` | Lookup(Pharmacy_Store__c) | Target pharmacy |
| `Medication__c` | Lookup(Medication__c) | Transferred medication |
| `Inventory_Position__c` | Lookup(Inventory_Position__c) | Target inventory record |
| `Quantity_Transferred__c` | Number(18,0) | Units moved (0 for blocked) |
| `Transfer_Status__c` | Picklist (restricted) | Pending, Completed, or Blocked |
| `Transfer_Date__c` | DateTime | Execution timestamp |
| `Notes__c` | Long Text (32KB) | Rationale, compliance block details, or error info |

---

## Transfer Engine

### Decision Flow

```
1. Load target inventory position
         │
         ▼
2. Is medication DEA Schedule II?
    ├── YES → HARD BLOCK (log Blocked, return compliance message, NO confirm prompt)
    │
    ▼ NO
3. Find surplus sources (Quantity > target Safety_Stock + 1, active stores)
         │
         ▼
4. Apply eligibility filters on each candidate:
    ├── Cold-chain capable? (if medication requires it)
    ├── Has DEA registration?
    └── Expiry > 30 days from today?
         │
         ▼
5. Any eligible source found?
    ├── NO → Return distributor fallback message (NO confirm prompt)
    │
    ▼ YES (first eligible = best, pre-sorted by qty DESC)
6. Calculate transfer qty = min(50% of source surplus, target need)
         │
         ▼
7. confirm = false?
    ├── YES → Write recommendation to record, return uhText with "Shall I proceed?"
    │
    ▼ confirm = true
8. Execute atomically (Savepoint):
    ├── Deduct from source
    ├── Add to target
    ├── Write Transfer_Log__c (Completed)
    └── Return execution confirmation with log reference
```

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `TRANSFER_BUFFER_PCT` | 50 | Transfer 50% of source surplus above safety stock |
| `MIN_DAYS_TO_EXPIRY` | 30 | Exclude source stock expiring within 30 days |
| `DEA_SCHEDULE_II` | "II" | Schedule that triggers hard compliance block |
| `PREVIEW_MAX_LENGTH` | 255 | Max chars for `Recommendation_Preview__c` Grid column |

### Transfer Quantity Formula

```
Source Surplus  = source.Quantity - source.Safety_Stock
Target Need     = target.Safety_Stock - target.Quantity
Proposed        = Source Surplus × 50%
Transfer Qty    = min(Proposed, Target Need)
```

---

## Agentforce Configuration

### Prompt Template: IST Inventory Recommendation

An Einstein Prompt Template that generates concise, rule-based inventory recommendations for the Grid column. The template receives inventory context via `$Input:Inventory_Position__c` merge fields and follows strict output rules: Schedule II medications always get a manual DEA Form 222 message, critical stock triggers a transfer recommendation, and near-expiry items get an alert prefix. Output is capped at 150 characters for Grid column fit.

### Agent Script: inventory_transfer_ops_agent

The Agentforce agent orchestrates the two-step transfer workflow:

1. **Dry Run** — Agent calls `Execute_Inter_Store_Transfer` flow with `confirm=false`. Surfaces the `uhText` recommendation verbatim.
2. **Compliance Gate** — If `success=false`, the agent does NOT offer a "Proceed?" prompt. The `uhText` already contains the user's next action.
3. **Confirmation** — If `success=true`, the agent asks "Shall I proceed with this transfer?" and waits for explicit user confirmation.
4. **Execution** — On confirmation, the agent calls the flow again with `confirm=true` and surfaces the execution result.

The agent enforces critical rules: it never executes without explicit confirmation, never bypasses Schedule II restrictions, and always surfaces `uhText` verbatim without paraphrasing compliance messages.

---

## Setup & Deployment

### Prerequisites

- Salesforce CLI (`sf` v2+)
- A Salesforce org with Agentforce enabled
- Node.js 18+ (for local dev tooling)

### Deploy to a Scratch Org

```bash
git clone https://github.com/jayavardhan-raju/Salesforce-AgentMemory.git
cd Salesforce-AgentMemory

sf org create scratch -f config/project-scratch-def.json -a IST -d 30
sf project deploy start -o IST
sf org assign permset -n IST_Ops_User -o IST
sf org open -o IST
```

### Deploy to Sandbox / Production

```bash
sf org login web -a MyOrg
sf project deploy start -x manifest/package.xml -o MyOrg
sf org assign permset -n IST_Ops_User -o MyOrg
```

### Post-Deployment: Load Test Data

Run the three Anonymous Apex scripts in order to set up test scenarios:

1. **Script 1** (`IST_Script1_Stores_Meds`) — Creates 3 pharmacy stores and 3 medications
2. **Script 2** (`IST_Script2_Inventory`) — Creates 7 inventory position records across 3 test cases
3. **Script 3** (`IST_Script3_Verify`) — Verifies all data and prints test case IDs for Agentforce Grid

### Post-Deployment: Configure Agentforce

1. Create the **IST Inventory Recommendation** prompt template
2. Deploy the **inventory_transfer_ops_agent** agent script
3. Add the `Inventory_Transfer_Ops` list view to your Agentforce Grid configuration
4. Wire the `Execute_Inter_Store_Transfer` flow as a Grid row action

---

## Test Cases

The system ships with three test scenarios that cover the full decision tree:

| Test Case | Target | Medication | Scenario | Expected Outcome |
|-----------|--------|-----------|----------|-----------------|
| **TC1: Happy Path** | CVS Downtown, Mounjaro, Qty=0 | Non-controlled, cold-chain | Two eligible sources (Walgreens North 250 units, CVS Westside 200 units) | Recommends Walgreens North (highest qty), calculates transfer, executes on confirm |
| **TC2: Schedule II Block** | CVS Downtown, Adderall, Qty=0 | DEA Schedule II | Compliance hard block fires before any source search | `success=false`, DEA Form 222 message, `Transfer_Log__c` status=Blocked |
| **TC3: No Eligible Source** | CVS Downtown, Mounjaro 5mg, Qty=0 | Non-controlled, cold-chain | Two candidates exist but both excluded by expiry filter (20d, 15d < 30d threshold) | `success=false`, distributor fallback message, no "Shall I proceed?" |

---

## Security

- All classes use `with sharing` to enforce record-level access
- `Security.stripInaccessible(AccessType.UPDATABLE, records)` applied before all update DML
- Object-level `isUpdateable()` and `isCreateable()` checks before DML
- `WITH USER_MODE` on all SOQL queries in `InventoryPositionSelector`
- Permission set `IST_Ops_User` grants CRUD on operational objects; `Transfer_Log__c` is create/read only (no edit/delete)
- Savepoint-based rollback on any execution failure

---

## Testing

Two test classes target ≥90% coverage:

- **`InterStoreTransferServiceTest`** — 8 test methods covering happy path (dry-run + execute), Schedule II block (dry-run + confirm=true), no source fallback, cold-chain mismatch, null ID, expired source exclusion
- **`InterStoreTransferActionTest`** — 3 test methods validating the Invocable Action wiring, Schedule II compliance, and null confirm handling

```bash
sf apex test run -n InterStoreTransferServiceTest,InterStoreTransferActionTest -r human -c -o IST
```

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── InterStoreTransferAction.cls         # @InvocableMethod — Agentforce entry point
│   ├── InterStoreTransferActionTest.cls     # Action layer tests
│   ├── InterStoreTransferService.cls        # Core business logic
│   ├── InterStoreTransferServiceTest.cls    # Service layer tests (8 methods)
│   ├── InventoryPositionSelector.cls        # All SOQL queries
│   └── ISTTestDataFactory.cls              # Shared test data builder
├── flows/
│   └── Execute_Inter_Store_Transfer.flow    # Auto-Launched Flow bridging agent → Apex
├── objects/
│   ├── Inventory_Position__c/               # Grid record + fields + list views
│   ├── Medication__c/                       # Medication master + DEA/cold-chain
│   ├── Pharmacy_Store__c/                   # Store locations + capabilities
│   └── Transfer_Log__c/                     # Immutable audit trail
└── permissionsets/
    └── IST_Ops_User                         # Operational permission set
```

---

## Author

**Jayavardhan Raju** — [GitHub](https://github.com/jayavardhan-raju)
