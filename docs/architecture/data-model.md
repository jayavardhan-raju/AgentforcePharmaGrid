---
layout: default
title: Data Model
parent: Architecture
nav_order: 2
---

# Data Model

Pharmacy IST uses four custom objects in a hub-and-spoke model centered on `Inventory_Position__c`.

---

## Entity-Relationship Diagram

```
┌─────────────────────────┐     ┌──────────────────────┐
│   Pharmacy_Store__c     │     │    Medication__c      │
│ ────────────────────    │     │ ──────────────────    │
│  District__c            │     │  NDC__c (Unique)      │
│  Latitude__c            │     │  DEA_Schedule__c      │
│  Longitude__c           │     │  Cold_Chain_Required__c│
│  Cold_Chain_Capable__c  │     └─────────┬────────────┘
│  DEA_Registration__c    │               │
│  Is_Active__c           │               │
└──────────┬──────────────┘               │
           │                              │
     Lookup│(Required)         Lookup (Required)
           │                              │
           ▼                              ▼
┌───────────────────────────────────────────────────┐
│              Inventory_Position__c                 │
│ ────────────────────────────────────────────────   │
│  Quantity__c (Required)    Safety_Stock__c         │
│  Expiry_Date__c            Status__c (Formula)     │
│  Status_Color__c (Formula) Store_Name__c (Formula) │
│  Medication_Name__c (Formula)                      │
│  Recommendation__c (Long Text 32KB)                │
│  Recommendation_Preview__c (Text 255)              │
└──────────────────────┬────────────────────────────┘
                       │
                  1:N  │ Lookup
                       ▼
          ┌──────────────────────────────┐
          │       Transfer_Log__c        │
          │ ──────────────────────────   │
          │  Source_Store__c (Lookup)     │
          │  Target_Store__c (Lookup)     │
          │  Medication__c (Lookup)       │
          │  Quantity_Transferred__c      │
          │  Transfer_Status__c          │
          │  Transfer_Date__c            │
          │  Notes__c (Long Text 32KB)   │
          └──────────────────────────────┘
```

---

## Pharmacy_Store__c

Represents a physical pharmacy location. Stores hold the capabilities that drive eligibility filtering: cold-chain handling and DEA registration.

| API Name | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `Name` | Text | Yes | — | Store name |
| `District__c` | Text(80) | No | — | Operational district for rollups and routing |
| `Latitude__c` | Number(9,6) | No | — | GPS latitude for geo-proximity |
| `Longitude__c` | Number(9,6) | No | — | GPS longitude for geo-proximity |
| `Cold_Chain_Capable__c` | Checkbox | No | false | Whether the store can handle cold-chain medications |
| `DEA_Registration__c` | Text(50) | No | — | DEA registration ID. Blank = ineligible for controlled substance transfers |
| `Is_Active__c` | Checkbox | No | true | Only active stores appear as transfer candidates |

---

## Medication__c

Master medication record. The `DEA_Schedule__c` and `Cold_Chain_Required__c` fields drive the compliance and eligibility logic in `InterStoreTransferService`.

| API Name | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `Name` | Text | Yes | — | Medication name |
| `NDC__c` | Text(30), Unique | Yes | — | National Drug Code — unique identifier across the system |
| `DEA_Schedule__c` | Picklist (restricted) | No | None | Values: II, III, IV, V, None. Schedule II triggers hard compliance block. |
| `Cold_Chain_Required__c` | Checkbox | No | false | If true, source stores must have `Cold_Chain_Capable__c = true` |

---

## Inventory_Position__c

The central record displayed in the Agentforce Grid. One record per store-medication combination. Contains the inventory state, computed status, and recommendation output fields.

| API Name | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `Store__c` | Lookup(Pharmacy_Store__c), Restrict Delete | Yes | — | Parent pharmacy store |
| `Medication__c` | Lookup(Medication__c), Restrict Delete | Yes | — | Parent medication |
| `Quantity__c` | Number(18,0) | Yes | — | Current on-hand quantity |
| `Safety_Stock__c` | Number(18,0) | No | — | Replenishment threshold. Transfer qty is capped at `Safety_Stock - Quantity` |
| `Expiry_Date__c` | Date | No | — | Current lot expiry. Source stock within 30 days of expiry is excluded |
| `Status__c` | Formula(Text) | — | — | Computed: OUT_OF_STOCK (Qty ≤ 0), LOW (Qty < Safety), HEALTHY, UNKNOWN |
| `Status_Color__c` | Formula(Text) | — | — | Maps Status to color: RED, ORANGE, GREEN, GRAY |
| `Store_Name__c` | Formula(Text) | — | — | `Store__r.Name` — for Grid display |
| `Medication_Name__c` | Formula(Text) | — | — | `Medication__r.Name` — for Grid display |
| `Recommendation__c` | Long Text Area (32KB) | No | — | Full recommendation/execution text for record detail page |
| `Recommendation_Preview__c` | Text(255) | No | — | Truncated preview for Agentforce Grid column (Long Text Area not supported in Grid) |

### List Views

- **All** — Default view showing all inventory positions
- **Inventory_Transfer_Ops** — Operational view with columns: Name, ID, Store, Medication, Quantity, Safety Stock, Expiry Date, Status, Status Color, Recommendation Preview, Recommendation, Created Date

---

## Transfer_Log__c

Immutable audit trail. Created on both successful transfers (status = Completed) and compliance blocks (status = Blocked). The permission set intentionally grants create + read only — no edit or delete — preserving audit integrity.

| API Name | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `Source_Store__c` | Lookup(Pharmacy_Store__c), SetNull | No | — | Source pharmacy (null for blocked transfers) |
| `Target_Store__c` | Lookup(Pharmacy_Store__c), SetNull | No | — | Target pharmacy |
| `Medication__c` | Lookup(Medication__c), SetNull | No | — | Transferred medication |
| `Inventory_Position__c` | Lookup(Inventory_Position__c), SetNull | No | — | Target inventory record evaluated |
| `Quantity_Transferred__c` | Number(18,0) | No | — | Units moved (0 for Blocked status) |
| `Transfer_Status__c` | Picklist (restricted) | No | Pending | Pending, Completed, or Blocked |
| `Transfer_Date__c` | DateTime | No | — | Execution or evaluation timestamp |
| `Notes__c` | Long Text Area (32KB) | No | — | Rationale, compliance block details, or error information |

---

## Permission Set: IST_Ops_User

Grants CRUD on `Inventory_Position__c`, `Medication__c`, and `Pharmacy_Store__c`. Grants **create + read only** on `Transfer_Log__c` (no edit, no delete) to preserve audit immutability. Includes field-level access to all operational fields including formula fields (read-only for Status and Status Color).
