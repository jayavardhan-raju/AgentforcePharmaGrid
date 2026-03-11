---
layout: default
title: LWC Components
parent: API Reference
nav_order: 2
---

# LWC Components

AgentforceGrid does not currently include custom Lightning Web Components. The user interface is provided entirely by the native **Agentforce Grid** component configured on the `Inventory_Position__c` object using the `Inventory Transfer Ops` list view.

---

## Grid Configuration

The Agentforce Grid displays the following columns from the `Inventory_Transfer_Ops` list view:

| Column | Field | Type | Purpose |
|--------|-------|------|---------|
| Inventory Position Number | `NAME` | AutoNumber | Record identifier (`INV-{000000}`) |
| Record ID | `OBJECT_ID` | ID | Salesforce record ID |
| Store | `Store__c` | Lookup | Pharmacy store reference |
| Medication | `Medication__c` | Lookup | Medication reference |
| Quantity | `Quantity__c` | Number | Current on-hand quantity |
| Safety Stock | `Safety_Stock__c` | Number | Replenishment threshold |
| Expiry Date | `Expiry_Date__c` | Date | Current lot expiry |
| Status | `Status__c` | Formula | `OUT_OF_STOCK`, `LOW`, `HEALTHY`, `UNKNOWN` |
| Status Color | `Status_Color__c` | Formula | `RED`, `ORANGE`, `GREEN`, `GRAY` |
| Recommendation Preview | `Recommendation_Preview__c` | Text(255) | Truncated transfer recommendation for Grid display |
| Recommendation | `Recommendation__c` | Long Text Area | Full recommendation (not displayable in Grid column) |
| Created Date | `CREATED_DATE` | DateTime | Record creation timestamp |

The Grid's action button triggers the `Execute_Inter_Store_Transfer` flow, which invokes the `InterStoreTransferAction` Apex invocable method.
