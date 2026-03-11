---
layout: default
title: Data Model
parent: Architecture
nav_order: 2
---

# Data Model

AgentforceGrid uses four custom objects that model a pharmacy distribution network with inventory tracking and an audit trail.

---

## Entity Relationship Diagram

```
┌──────────────────────┐          ┌──────────────────────────────┐
│   Pharmacy_Store__c  │          │       Medication__c           │
│──────────────────────│          │──────────────────────────────│
│ Name (Text)          │          │ Name (Text)                  │
│ District__c          │          │ NDC__c (Unique)              │
│ Latitude__c          │          │ DEA_Schedule__c (Picklist)   │
│ Longitude__c         │          │ Cold_Chain_Required__c (CB)  │
│ Cold_Chain_Capable__c│          └──────────┬───────────────────┘
│ DEA_Registration__c  │                     │
│ Is_Active__c         │                     │
└──────┬───────────────┘                     │
       │                                     │
       │  Lookup (Store__c)                  │  Lookup (Medication__c)
       │  [Required, Restrict]               │  [Required, Restrict]
       │                                     │
       ▼                                     ▼
┌──────────────────────────────────────────────────────────────┐
│                  Inventory_Position__c                         │
│──────────────────────────────────────────────────────────────│
│ Name: INV-{000000} (AutoNumber)                               │
│ Store__c → Pharmacy_Store__c                                  │
│ Medication__c → Medication__c                                 │
│ Quantity__c (Number, Required)                                │
│ Safety_Stock__c (Number)                                      │
│ Expiry_Date__c (Date)                                         │
│ Status__c (Formula)                                           │
│ Status_Color__c (Formula)                                     │
│ Store_Name__c (Formula)                                       │
│ Medication_Name__c (Formula)                                  │
│ Recommendation__c (Long Text Area)                            │
│ Recommendation_Preview__c (Text 255)                          │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       │  Lookup (Inventory_Position__c)
                       │  [SetNull]
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                     Transfer_Log__c                            │
│──────────────────────────────────────────────────────────────│
│ Name: TRN-{000000} (AutoNumber)                               │
│ Source_Store__c → Pharmacy_Store__c [SetNull]                 │
│ Target_Store__c → Pharmacy_Store__c [SetNull]                 │
│ Medication__c → Medication__c [SetNull]                       │
│ Inventory_Position__c → Inventory_Position__c [SetNull]       │
│ Quantity_Transferred__c (Number)                              │
│ Transfer_Status__c (Picklist: Pending/Completed/Blocked)      │
│ Transfer_Date__c (DateTime)                                   │
│ Notes__c (Long Text Area)                                     │
└──────────────────────────────────────────────────────────────┘
```

---

## Pharmacy_Store__c

Represents a physical pharmacy store location in the distribution network.

| API Name | Type | Length | Required | Unique | Description |
|----------|------|--------|----------|--------|-------------|
| `Name` | Text | — | Yes | No | Pharmacy Store Name |
| `District__c` | Text | 80 | No | No | Operational district of the store |
| `Latitude__c` | Number | (9,6) | No | No | Store latitude coordinate |
| `Longitude__c` | Number | (9,6) | No | No | Store longitude coordinate |
| `Cold_Chain_Capable__c` | Checkbox | — | — | — | Whether the store can handle cold-chain medications. Default: `false` |
| `DEA_Registration__c` | Text | 50 | No | No | DEA registration identifier for controlled substances handling |
| `Is_Active__c` | Checkbox | — | — | — | Whether the store is active for operations. Default: `true` |

**Sharing Model:** ReadWrite  
**External Sharing:** Private

---

## Medication__c

Represents a medication with regulatory and handling attributes.

| API Name | Type | Length | Required | Unique | Description |
|----------|------|--------|----------|--------|-------------|
| `Name` | Text | — | Yes | No | Medication Name |
| `NDC__c` | Text | 30 | Yes | Yes | National Drug Code (unique identifier). 10- or 11-digit NDC with labeler, product, and package codes. |
| `DEA_Schedule__c` | Picklist | — | No | — | DEA controlled-substance schedule. Values: `II`, `III`, `IV`, `V`, `None`. Default: `None`. Restricted picklist. |
| `Cold_Chain_Required__c` | Checkbox | — | — | — | Whether this medication requires cold-chain handling. Default: `false` |

**Sharing Model:** ReadWrite  
**External Sharing:** Private

### DEA_Schedule__c Picklist Values

| Value | Label | Default |
|-------|-------|---------|
| `II` | II | No |
| `III` | III | No |
| `IV` | IV | No |
| `V` | V | No |
| `None` | None | Yes |

---

## Inventory_Position__c

Inventory position of a specific Medication at a specific Pharmacy Store. The central object of the Agentforce Grid.

| API Name | Type | Length | Required | Description |
|----------|------|--------|----------|-------------|
| `Name` | AutoNumber | — | — | Format: `INV-{000000}` |
| `Store__c` | Lookup | — | Yes | → `Pharmacy_Store__c`. Delete constraint: Restrict. |
| `Medication__c` | Lookup | — | Yes | → `Medication__c`. Delete constraint: Restrict. |
| `Quantity__c` | Number | (18,0) | Yes | On-hand quantity of medication units |
| `Safety_Stock__c` | Number | (18,0) | No | Safety stock threshold below which replenishment is recommended |
| `Expiry_Date__c` | Date | — | No | Expiry date of the current lot |
| `Status__c` | Formula(Text) | — | — | `OUT_OF_STOCK` if qty ≤ 0; `LOW` if qty < safety stock; `HEALTHY` if qty ≥ safety stock; `UNKNOWN` if safety stock is blank |
| `Status_Color__c` | Formula(Text) | — | — | `RED` for OUT_OF_STOCK, `ORANGE` for LOW, `GREEN` for HEALTHY, `GRAY` for UNKNOWN |
| `Store_Name__c` | Formula(Text) | — | — | `Store__r.Name` |
| `Medication_Name__c` | Formula(Text) | — | — | `Medication__r.Name` |
| `Recommendation__c` | Long Text Area | 32768 | No | Full recommendation text for record detail view |
| `Recommendation_Preview__c` | Text | 255 | No | Truncated recommendation for Agentforce Grid column display |

**Sharing Model:** ReadWrite  
**External Sharing:** Private

### List Views

| List View | Label | Filter Scope | Columns |
|-----------|-------|-------------|---------|
| `All` | All | Everything | Default |
| `Inventory_Transfer_Ops` | Inventory Transfer Ops | Mine | NAME, OBJECT_ID, Store__c, Medication__c, Quantity__c, Safety_Stock__c, Expiry_Date__c, Status__c, Status_Color__c, Recommendation_Preview__c, Recommendation__c, CREATED_DATE |

---

## Transfer_Log__c

Immutable audit trail for inter-store transfers and compliance outcomes.

| API Name | Type | Length | Required | Description |
|----------|------|--------|----------|-------------|
| `Name` | AutoNumber | — | — | Format: `TRN-{000000}` |
| `Source_Store__c` | Lookup | — | No | → `Pharmacy_Store__c`. Delete constraint: SetNull. |
| `Target_Store__c` | Lookup | — | No | → `Pharmacy_Store__c`. Delete constraint: SetNull. |
| `Medication__c` | Lookup | — | No | → `Medication__c`. Delete constraint: SetNull. |
| `Inventory_Position__c` | Lookup | — | No | → `Inventory_Position__c`. Delete constraint: SetNull. |
| `Quantity_Transferred__c` | Number | (18,0) | No | Quantity moved from source to target. 0 for compliance-blocked transfers. |
| `Transfer_Status__c` | Picklist | — | No | `Pending` (default), `Completed`, `Blocked`. Restricted picklist. |
| `Transfer_Date__c` | DateTime | — | No | Date/time the transfer was executed or evaluated |
| `Notes__c` | Long Text Area | 32768 | No | Details about the recommendation, rationale, or compliance block |

**Sharing Model:** ReadWrite  
**External Sharing:** Private

### Transfer_Status__c Picklist Values

| Value | Label | Default | Usage |
|-------|-------|---------|-------|
| `Pending` | Pending | Yes | Default value (not currently used by code) |
| `Completed` | Completed | No | Written by `executeTransfer()` on successful atomic execution |
| `Blocked` | Blocked | No | Written by `logComplianceBlock()` for Schedule II denials |

---

## Relationship Summary

| Relationship | Type | Delete Constraint | Description |
|-------------|------|-------------------|-------------|
| `Inventory_Position__c.Store__c` → `Pharmacy_Store__c` | Lookup | Restrict | A store cannot be deleted if it has inventory positions |
| `Inventory_Position__c.Medication__c` → `Medication__c` | Lookup | Restrict | A medication cannot be deleted if it has inventory positions |
| `Transfer_Log__c.Source_Store__c` → `Pharmacy_Store__c` | Lookup | SetNull | Source store reference nulled if store is deleted |
| `Transfer_Log__c.Target_Store__c` → `Pharmacy_Store__c` | Lookup | SetNull | Target store reference nulled if store is deleted |
| `Transfer_Log__c.Medication__c` → `Medication__c` | Lookup | SetNull | Medication reference nulled if medication is deleted |
| `Transfer_Log__c.Inventory_Position__c` → `Inventory_Position__c` | Lookup | SetNull | Inventory position reference nulled if position is deleted |
