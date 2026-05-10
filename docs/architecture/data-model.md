---
layout: default
title: Data Model
parent: Architecture
nav_order: 2
---

# Data Model

Four custom objects make up the AgentforcePharmaGrid domain. Three are entities (`Pharmacy_Store__c`, `Medication__c`, `Inventory_Position__c`) and one is an immutable audit log (`Transfer_Log__c`).

---

## ER Diagram

```
+---------------------+         +-------------------------+         +----------------------+
|  Pharmacy_Store__c  |         |   Inventory_Position__c |         |    Medication__c     |
+---------------------+         +-------------------------+         +----------------------+
| Name                |<--------|  Store__c (Lookup)      |-------->| Name                 |
| District__c         |         |  Medication__c (Lookup) |         | NDC__c (unique)      |
| Latitude__c         |         |  Quantity__c            |         | DEA_Schedule__c      |
| Longitude__c        |         |  Safety_Stock__c        |         | Cold_Chain_Required__c|
| Cold_Chain_Capable__c|        |  Expiry_Date__c         |         +----------------------+
| DEA_Registration__c |         |  Recommendation__c      |
| Is_Active__c        |         |  Recommendation_Preview__c|
+---------------------+         |  Status__c (formula)    |
       ^      ^                 |  Status_Color__c (frml) |
       |      |                 |  Store_Name__c (frml)   |
       |      |                 |  Medication_Name__c(frml)|
       |      |                 +-------------------------+
       |      |                              ^
       |      |                              |
+--------------------+--------+---------------+
|       Transfer_Log__c                       |
+---------------------------------------------+
| Source_Store__c   (Lookup → Pharmacy_Store) |
| Target_Store__c   (Lookup → Pharmacy_Store) |
| Medication__c     (Lookup → Medication)     |
| Inventory_Position__c (Lookup → Inv_Pos)    |
| Quantity_Transferred__c                     |
| Transfer_Date__c                            |
| Transfer_Status__c (Pending/Completed/Blocked)|
| Notes__c                                    |
+---------------------------------------------+
```

**Cardinality summary**

- One `Pharmacy_Store__c` has many `Inventory_Position__c` records (one per medication it stocks).
- One `Medication__c` has many `Inventory_Position__c` records (one per store that stocks it).
- One `Inventory_Position__c` has many `Transfer_Log__c` records (one per transfer evaluation, completed or blocked).
- `Pharmacy_Store__c` lookups on `Transfer_Log__c` are split into `Source_Store__c` and `Target_Store__c` so a single store row can be either side of a transfer.

---

## `Pharmacy_Store__c`

**Description:** Represents a pharmacy store location.
**Sharing model:** ReadWrite, Private external sharing.
**Visibility:** Public.
**Name field:** Text, label "Pharmacy Store Name".

| Field API Name | Type | Length / Precision | Required | Default | Description |
|---|---|---|---|---|---|
| `Name` | Text | — | Yes | — | Pharmacy Store Name |
| `District__c` | Text | 80 | No | — | Operational district of the store |
| `Latitude__c` | Number | (9, 6) | No | — | Store latitude |
| `Longitude__c` | Number | (9, 6) | No | — | Store longitude |
| `Cold_Chain_Capable__c` | Checkbox | — | No | `false` | Indicates if the store can handle cold chain medications |
| `DEA_Registration__c` | Text | 50 | No | — | DEA registration identifier; **source stores must have a non-blank value to be eligible** |
| `Is_Active__c` | Checkbox | — | No | `true` | Inactive stores are excluded from `findSurplusSources()` |

---

## `Medication__c`

**Description:** Represents a medication with regulatory and handling attributes.
**Sharing model:** ReadWrite, Private external sharing.
**Visibility:** Public.
**Name field:** Text, label "Medication Name".

| Field API Name | Type | Length / Picklist | Required | Default | Description |
|---|---|---|---|---|---|
| `Name` | Text | — | Yes | — | Medication Name |
| `NDC__c` | Text, unique | 30 | Yes | — | National Drug Code (10/11-digit, labeler/product/package codes) |
| `DEA_Schedule__c` | Picklist (restricted) | `II`, `III`, `IV`, `V`, `None` | No | `None` | `II` triggers the compliance hard-stop |
| `Cold_Chain_Required__c` | Checkbox | — | No | `false` | When `true`, only cold-chain-capable source stores are eligible |

---

## `Inventory_Position__c`

**Description:** Inventory position of a specific Medication at a specific Pharmacy Store.
**Sharing model:** ReadWrite, Private external sharing.
**Visibility:** Public.
**Name field:** Auto Number, format `INV-{000000}`.
**Record page override:** `Inventory_Position_Record_Page` (Flexipage) for both Large and Small form factors.

| Field API Name | Type | Length / Precision / Formula | Required | Default | Description |
|---|---|---|---|---|---|
| `Store__c` | Lookup → `Pharmacy_Store__c` | Restrict on delete | Yes | — | Reference to the Pharmacy Store |
| `Medication__c` | Lookup → `Medication__c` | Restrict on delete | Yes | — | Reference to the Medication |
| `Quantity__c` | Number | (18, 0) | Yes | — | On-hand quantity |
| `Safety_Stock__c` | Number | (18, 0) | No | — | Threshold below which replenishment is recommended |
| `Expiry_Date__c` | Date | — | No | — | Expiry date of the current lot |
| `Recommendation__c` | Long Text Area | 32,768 | No | — | Long-form recommendation text written by `buildRecommendation()` |
| `Recommendation_Preview__c` | Text | 255 | No | — | Truncated preview rendered in the Agentforce Grid column |
| `Status__c` | Formula (Text) | `OUT_OF_STOCK`/`LOW`/`HEALTHY`/`UNKNOWN` | — | — | Computed from `Quantity__c` vs `Safety_Stock__c` |
| `Status_Color__c` | Formula (Text) | `RED`/`ORANGE`/`GREEN`/`GRAY` | — | — | Derived from `Status__c` |
| `Store_Name__c` | Formula (Text) | `Store__r.Name` | — | — | Flattened for Grid display |
| `Medication_Name__c` | Formula (Text) | `Medication__r.Name` | — | — | Flattened for Grid display |

### `Status__c` formula

```
IF(
  ISBLANK(Safety_Stock__c),
  "UNKNOWN",
  IF(
    Quantity__c <= 0,
    "OUT_OF_STOCK",
    IF(
      Quantity__c < Safety_Stock__c,
      "LOW",
      "HEALTHY"
    )
  )
)
```

`formulaTreatBlanksAs = BlankAsZero`.

### `Status_Color__c` formula

```
CASE(
  Status__c,
  "OUT_OF_STOCK", "RED",
  "LOW",          "ORANGE",
  "HEALTHY",      "GREEN",
  "UNKNOWN",      "GRAY",
  "GRAY"
)
```

### List Views

- **All** — default unfiltered.
- **Inventory_Transfer_Ops** — filterScope `Mine`, columns: `NAME`, `OBJECT_ID`, `Store__c`, `Medication__c`, `Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Status__c`, `Status_Color__c`, `Recommendation_Preview__c`, `Recommendation__c`, `CREATED_DATE`. This is the list view the Agentforce Grid is typically bound to.

---

## `Transfer_Log__c`

**Description:** Immutable audit trail for inter-store transfers and compliance outcomes.
**Sharing model:** ReadWrite, Private external sharing.
**Visibility:** Public.
**Name field:** Auto Number, format `TRN-{000000}`.
**Record page override:** `Transfer_Log_Record_Page` (Flexipage) for both Large and Small form factors.
**Permission semantics:** under `IST_Ops_User`, this object is **create + read only** — `allowEdit = false`, `allowDelete = false`.

| Field API Name | Type | Length / Picklist | Required | Default | Description |
|---|---|---|---|---|---|
| `Source_Store__c` | Lookup → `Pharmacy_Store__c` | SetNull on delete | No | — | Null on `Blocked` Schedule II logs |
| `Target_Store__c` | Lookup → `Pharmacy_Store__c` | SetNull on delete | No | — | The store with the critical position |
| `Medication__c` | Lookup → `Medication__c` | SetNull on delete | No | — | Medication associated with the transfer |
| `Inventory_Position__c` | Lookup → `Inventory_Position__c` | SetNull on delete | No | — | Target position evaluated |
| `Quantity_Transferred__c` | Number | (18, 0) | No | — | `0` for blocked entries |
| `Transfer_Date__c` | DateTime | — | No | — | Set to `DateTime.now()` |
| `Transfer_Status__c` | Picklist (restricted) | `Pending`, `Completed`, `Blocked` | No | `Pending` | Lifecycle |
| `Notes__c` | Long Text Area | 32,768 | No | — | Rationale, source/target names, compliance reason |

### Layout: `Transfer_Log__c-Transfer Log Layout`

The standard layout exposes `Name`, `Inventory_Position__c`, `Notes__c`, `Medication__c`, `Transfer_Date__c`, `Transfer_Status__c`, `OwnerId`, `Quantity_Transferred__c`, `Source_Store__c` (and presumably `Target_Store__c`). The layout excludes the `OpenSlackRecordChannel` and `Submit` standard buttons.

---

## Why `Recommendation_Preview__c` Exists

The Agentforce Grid does **not** support Long Text Area fields as renderable columns. The full recommendation written by `InterStoreTransferService.buildRecommendation()` typically exceeds 255 characters because it includes the medication name, source store name, available stock, days to expiry, cold-chain confirmation, DEA schedule, and proposed transfer quantity in a single string.

To get this content into a Grid column, the service writes the same content into two fields:

- **`Recommendation__c`** (Long Text Area, 32768) — full text, for the record detail view and any process that consumes it programmatically.
- **`Recommendation_Preview__c`** (Text, 255) — the same content truncated to `PREVIEW_MAX_LENGTH - 3` and suffixed with `...` if it exceeded the limit. This is the field bound to the Grid's recommendation column.

After execution, `Recommendation_Preview__c` is overwritten with a completion message (`"Transfer completed: N units from <store>. See Transfer Log for details."`) so the Grid row reflects post-execution state.
