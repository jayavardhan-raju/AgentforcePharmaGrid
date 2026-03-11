# AgentforceGrid

**Agentforce-powered inter-store inventory transfer system for pharmacy networks — with DEA compliance, cold-chain validation, and atomic audit trails.**

---

## Overview

AgentforceGrid automates the process of rebalancing medication inventory across pharmacy store locations using Salesforce Agentforce. When a store's stock of a medication drops below its safety threshold, an operations user can trigger a transfer recommendation directly from an Agentforce Grid. The system identifies the best source store in the network, validates compliance and logistics constraints, and either recommends or executes the transfer — all within a two-step conversational workflow.

The system is built specifically for regulated pharmacy operations. It enforces DEA Schedule II controlled substance restrictions (requiring manual DEA Form 222 for those medications), validates cold-chain handling capability between source and target stores, excludes near-expiry stock from transfers, and writes an immutable audit trail for every action — including denied requests.

The architecture follows a clean Action → Service → Selector pattern with no triggers. All business logic is isolated in the service layer, all SOQL is isolated in the selector, and the invocable action layer is a thin adapter for Agentforce.

### Key Capabilities

- **Two-Step Agent Workflow** — First call (`confirm=false`) returns a dry-run recommendation with source store, quantity, and compliance details. Second call (`confirm=true`) executes the transfer atomically.
- **DEA Schedule II Hard Stop** — Medications classified as Schedule II are automatically blocked with no source search, no confirm prompt, and a compliance block audit log. The agent surfaces a DEA Form 222 instruction.
- **Cold-Chain Validation** — Source stores are only eligible if they have cold-chain capability when the medication requires it (`Cold_Chain_Required__c` → `Cold_Chain_Capable__c`).
- **Expiry Threshold Filtering** — Source stock expiring within 30 days (`MIN_DAYS_TO_EXPIRY = 30`) is excluded from transfer candidates.
- **Smart Quantity Calculation** — Transfers 50% of the source surplus above safety stock (`TRANSFER_BUFFER_PCT = 50`), capped at the target's exact need to reach its own safety stock.
- **Atomic Execution with Rollback** — Confirmed transfers use `Database.setSavepoint()` with full rollback on any failure. No partial inventory updates are possible.
- **Immutable Audit Trail** — Every transfer creates a `Transfer_Log__c` record. Compliance blocks also generate audit logs with `Transfer_Status__c = 'Blocked'`.
- **FLS/CRUD Enforcement** — All DML checks `Schema.sObjectType` for updateability/createability. `Security.stripInaccessible()` is applied before inventory updates.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AGENTFORCE GRID UI                         │
│              (Inventory_Position__c List View)                   │
│         Ops user clicks "Transfer/Optimize" on a row            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              Execute_Inter_Store_Transfer (Flow)                 │
│         AutoLaunchedFlow — passes inventoryPositionId            │
│         Input: inventoryPositionId, confirm                      │
│         Output: success, uhText, sourceStoreId, transferLogId    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InterStoreTransferAction (Invocable Action)            │
│   @InvocableMethod — thin adapter, maps ActionInput/Output       │
│   Delegates ALL logic to InterStoreTransferService               │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InterStoreTransferService (Service Layer)              │
│   Core business logic:                                           │
│     • DEA Schedule II compliance gate                            │
│     • Source store selection (cold-chain, DEA reg, expiry)        │
│     • Transfer quantity calculation (50% buffer, capped)         │
│     • Dry-run recommendation (writes Recommendation__c)          │
│     • Atomic execution (Savepoint + Transfer_Log__c)             │
│     • FLS/CRUD enforcement + stripInaccessible                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│           InventoryPositionSelector (Selector Layer)             │
│   Read-only SOQL:                                                │
│     • getById() — full context query with Store + Medication     │
│     • findSurplusSources() — surplus candidates, sorted by qty   │
│   All queries use USER_MODE for row-level security               │
└─────────────────────────────────────────────────────────────────┘
```

| Layer | Class | Responsibility |
|-------|-------|----------------|
| Flow | `Execute_Inter_Store_Transfer` | Agentforce entry point — passes `inventoryPositionId` to the invocable action, sets `refreshView = true` on completion |
| Action | `InterStoreTransferAction` | `@InvocableMethod` adapter — maps `ActionInput`/`ActionOutput` wrappers, delegates to service |
| Service | `InterStoreTransferService` | All business logic — compliance checks, source selection, quantity calculation, dry-run recommendations, atomic execution, audit logging |
| Selector | `InventoryPositionSelector` | All SOQL — `getById()` and `findSurplusSources()` with full relational context, `USER_MODE` enforcement |
| Test Factory | `ISTTestDataFactory` | Shared test data creation for stores, medications, and inventory positions |

---

## Data Model

### Pharmacy_Store__c

Represents a physical pharmacy store location in the distribution network.

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Name` | Text | Yes | Pharmacy Store Name |
| `District__c` | Text(80) | No | Operational district of the store |
| `Latitude__c` | Number(9,6) | No | Store latitude coordinate |
| `Longitude__c` | Number(9,6) | No | Store longitude coordinate |
| `Cold_Chain_Capable__c` | Checkbox | — | Whether the store can handle cold-chain medications (default: `false`) |
| `DEA_Registration__c` | Text(50) | No | DEA registration identifier for controlled substances handling |
| `Is_Active__c` | Checkbox | — | Whether the store is active for operations (default: `true`) |

### Medication__c

Represents a medication with regulatory and handling attributes.

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Name` | Text | Yes | Medication Name |
| `NDC__c` | Text(30) | Yes | National Drug Code — unique identifier (unique field) |
| `DEA_Schedule__c` | Picklist | No | DEA controlled-substance schedule: `II`, `III`, `IV`, `V`, `None` (default: `None`) |
| `Cold_Chain_Required__c` | Checkbox | — | Whether this medication requires cold-chain handling (default: `false`) |

### Inventory_Position__c

Inventory position of a specific Medication at a specific Pharmacy Store. Auto-numbered as `INV-{000000}`.

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Name` | AutoNumber | — | `INV-{000000}` |
| `Store__c` | Lookup(Pharmacy_Store__c) | Yes | Reference to the Pharmacy Store (Restrict delete) |
| `Medication__c` | Lookup(Medication__c) | Yes | Reference to the Medication (Restrict delete) |
| `Quantity__c` | Number(18,0) | Yes | On-hand quantity |
| `Safety_Stock__c` | Number(18,0) | No | Safety stock threshold below which replenishment is recommended |
| `Expiry_Date__c` | Date | No | Expiry date of the current lot |
| `Status__c` | Formula(Text) | — | Computed: `OUT_OF_STOCK` (qty ≤ 0), `LOW` (qty < safety), `HEALTHY`, `UNKNOWN` |
| `Status_Color__c` | Formula(Text) | — | Color code: `RED`, `ORANGE`, `GREEN`, `GRAY` based on `Status__c` |
| `Store_Name__c` | Formula(Text) | — | `Store__r.Name` |
| `Medication_Name__c` | Formula(Text) | — | `Medication__r.Name` |
| `Recommendation__c` | Long Text Area(32768) | No | Full recommendation text for record detail view |
| `Recommendation_Preview__c` | Text(255) | No | Truncated recommendation for Agentforce Grid column display |

### Transfer_Log__c

Immutable audit trail for inter-store transfers and compliance outcomes. Auto-numbered as `TRN-{000000}`.

| API Name | Type | Required | Description |
|----------|------|----------|-------------|
| `Name` | AutoNumber | — | `TRN-{000000}` |
| `Source_Store__c` | Lookup(Pharmacy_Store__c) | No | Source store for the transfer (SetNull on delete) |
| `Target_Store__c` | Lookup(Pharmacy_Store__c) | No | Target store for the transfer (SetNull on delete) |
| `Medication__c` | Lookup(Medication__c) | No | Medication associated with this transfer (SetNull on delete) |
| `Inventory_Position__c` | Lookup(Inventory_Position__c) | No | Target inventory position evaluated (SetNull on delete) |
| `Quantity_Transferred__c` | Number(18,0) | No | Quantity moved from source to target (0 for blocked) |
| `Transfer_Status__c` | Picklist | No | `Pending` (default), `Completed`, `Blocked` |
| `Transfer_Date__c` | DateTime | No | Date/time the transfer was executed or evaluated |
| `Notes__c` | Long Text Area(32768) | No | Details about the recommendation, rationale, or compliance block |

---

## Transfer Quantity Calculation

The transfer quantity engine uses a conservative approach to avoid destabilizing the source store:

```
sourceSurplus = source.Quantity__c - source.Safety_Stock__c
targetNeed    = target.Safety_Stock__c - target.Quantity__c
proposed      = sourceSurplus × 50% (TRANSFER_BUFFER_PCT)
transferQty   = MIN(proposed, targetNeed)
```

**Worked Example:**

| Variable | Value |
|----------|-------|
| Source Quantity | 200 units |
| Source Safety Stock | 50 units |
| Source Surplus | 150 units |
| Target Quantity | 0 units |
| Target Safety Stock | 50 units |
| Target Need | 50 units |
| Proposed (50% of surplus) | 75 units |
| **Transfer Qty** (capped at need) | **50 units** |

### Source Selection Eligibility Rules

All of the following must pass for a source store to be eligible:

1. **Cold-chain match** — If `Medication__c.Cold_Chain_Required__c = true`, the source `Store__r.Cold_Chain_Capable__c` must also be `true`
2. **DEA registration** — Source `Store__r.DEA_Registration__c` must not be blank
3. **Expiry threshold** — Source stock `Expiry_Date__c` must be ≥ 30 days from today
4. **Active store** — Source `Store__r.Is_Active__c = true` (enforced in SOQL WHERE clause)
5. **Surplus above safety** — Source `Quantity__c > target.Safety_Stock__c + 1` (enforced in SOQL WHERE clause)

Candidates are sorted by `Quantity__c DESC` — the first eligible candidate is the best available source.

---

## Setup & Deployment

### Prerequisites

- Salesforce org with **Agentforce** enabled (API v65.0+)
- Salesforce CLI (`sf`) installed
- A Dev Hub enabled (for scratch orgs) or target sandbox/production org

### Deploy to a Scratch Org

```bash
git clone https://github.com/jayavardhan-raju/AgentforceGrid.git
cd AgentforceGrid

sf org create scratch -f config/project-scratch-def.json -a AgentforceGrid -d 30
sf project deploy start -o AgentforceGrid
sf org assign permset -n IST_Ops_User -o AgentforceGrid
sf org open -o AgentforceGrid
```

### Deploy to a Sandbox or Production

```bash
sf project deploy start \
  --target-org <your-org-alias> \
  --source-dir force-app
```

### Post-Deployment Configuration

1. **Assign Permission Set** — Assign `IST_Ops_User` to all operations users who will use the Agentforce Grid
2. **Activate the Flow** — Verify `Execute_Inter_Store_Transfer` flow is Active in Setup → Flows
3. **Configure Agentforce Grid** — Set up the Agentforce Grid on the `Inventory_Position__c` object with the `Inventory Transfer Ops` list view
4. **Map the Invocable Action** — Connect the `Execute Inter-Store Transfer` action to the Grid's Transfer/Optimize button
5. **Load Sample Data** — Run the 3 Apex data scripts **in order**:

```bash
# Script 1: Create 6 Pharmacy Stores (2 districts, varied capabilities)
sf apex run --file scripts/data/1_Create_Pharmacy_Stores.apex --target-org <your-org-alias>

# Script 2: Create 6 Medications (Schedule II, cold-chain, standard)
sf apex run --file scripts/data/2_Create_Medications.apex --target-org <your-org-alias>

# Script 3: Create 16 Inventory Positions (6 demo scenarios)
sf apex run --file scripts/data/3_Create_Inventory_Positions.apex --target-org <your-org-alias>
```

The scripts create a complete demo dataset with 6 pre-built scenarios: happy path cold-chain transfer, Schedule II compliance block, no-source distributor fallback, near-expiry source exclusion, Schedule IV allowed transfer, and multi-source selection. See [Deployment Guide](https://jayavardhan-raju.github.io/AgentforceGrid/setup/deployment.html) for full details on each scenario.

---

## Security

- **Sharing Model** — All classes use `with sharing`, enforcing the running user's record-level access
- **SOQL Mode** — All queries use `WITH USER_MODE` for row-level security enforcement
- **CRUD Checks** — `Schema.sObjectType.*.isUpdateable()` and `isCreateable()` are checked before every DML operation
- **FLS Enforcement** — `Security.stripInaccessible(AccessType.UPDATABLE, ...)` is applied to inventory position updates
- **Permission Set** — `IST_Ops_User` grants CRUD on `Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c` and Create+Read on `Transfer_Log__c` (no edit/delete on audit logs)
- **Transfer_Log__c Immutability** — The permission set grants only Create and Read on Transfer Logs — no Edit or Delete — ensuring the audit trail cannot be modified after creation

---

## Testing

### Run All Tests

```bash
sf apex run test \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --target-org <your-org-alias>
```

### Test Classes

| Test Class | Covers | Scenarios |
|------------|--------|-----------|
| `InterStoreTransferServiceTest` | `InterStoreTransferService`, `InventoryPositionSelector` | Happy path dry-run, happy path execution, Schedule II block (dry-run + confirm=true), no source fallback, cold-chain mismatch, null ID handling, expired source exclusion |
| `InterStoreTransferActionTest` | `InterStoreTransferAction` | Happy path dry-run output mapping, Schedule II compliance block, null confirm defaults to false |
| `ISTTestDataFactory` | — | Shared test data factory (covered transitively) |

### Test Coverage Map

- `InterStoreTransferService` — 7 test methods covering: recommendation flow, execution with Transfer_Log__c creation, Schedule II hard stop (both confirm=false and confirm=true), distributor fallback, cold-chain filtering, expiry filtering, null ID error handling
- `InterStoreTransferAction` — 3 test methods covering: dry-run output wiring, compliance block output, null confirm default behavior
- `InventoryPositionSelector` — Covered transitively through service and action tests (both `getById` and `findSurplusSources` are exercised)

---

## Project Structure

```
force-app/
└── main/
    └── default/
        ├── classes/
        │   ├── InterStoreTransferAction.cls          # Invocable Action (Agentforce entry)
        │   ├── InterStoreTransferAction.cls-meta.xml
        │   ├── InterStoreTransferActionTest.cls       # Action layer tests
        │   ├── InterStoreTransferActionTest.cls-meta.xml
        │   ├── InterStoreTransferService.cls          # Core service logic
        │   ├── InterStoreTransferService.cls-meta.xml
        │   ├── InterStoreTransferServiceTest.cls      # Service layer tests
        │   ├── InterStoreTransferServiceTest.cls-meta.xml
        │   ├── InventoryPositionSelector.cls          # SOQL selector
        │   ├── InventoryPositionSelector.cls-meta.xml
        │   ├── ISTTestDataFactory.cls                 # Test data factory
        │   └── ISTTestDataFactory.cls-meta.xml
        ├── flows/
        │   └── Execute_Inter_Store_Transfer.flow-meta.xml
        ├── objects/
        │   ├── Inventory_Position__c/
        │   │   ├── fields/                            # 12 fields
        │   │   └── listViews/                         # All, Inventory Transfer Ops
        │   ├── Medication__c/
        │   │   └── fields/                            # 3 fields
        │   ├── Pharmacy_Store__c/
        │   │   └── fields/                            # 6 fields
        │   └── Transfer_Log__c/
        │       └── fields/                            # 8 fields
        └── permissionsets/
            └── IST_Ops_User.permissionset-meta.xml
scripts/
└── data/
    ├── 1_Create_Pharmacy_Stores.apex          # Script 1: 6 stores, 2 districts
    ├── 2_Create_Medications.apex              # Script 2: 6 meds, varied DEA schedules
    └── 3_Create_Inventory_Positions.apex      # Script 3: 16 positions, 6 demo scenarios
```

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m "Add my feature"`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

Please ensure all new code includes test coverage targeting 90%+ and follows the Action → Service → Selector pattern.

---

## Author

**Jayavardhan Raju** — [GitHub](https://github.com/jayavardhan-raju)
