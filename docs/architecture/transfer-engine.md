---
layout: default
title: Transfer Engine
parent: Architecture
nav_order: 3
---

# Transfer Engine

This page documents the rules, math, and control flow inside `InterStoreTransferService.evaluate()`. Everything else in the project — the Flow, the action, the Grid binding — is wiring around this core.

---

## The Four Constants

Every policy decision the engine makes is parameterised by one of four `private static final` constants:

| Constant | Value | Effect |
|---|---|---|
| `TRANSFER_BUFFER_PCT` | `50` | Proposed transfer is this percentage of the source's surplus above its safety stock |
| `MIN_DAYS_TO_EXPIRY` | `30` | Source stock expiring within this window is excluded from candidates |
| `DEA_SCHEDULE_II` | `'II'` | Picklist value on `Medication__c.DEA_Schedule__c` that triggers the compliance hard-stop |
| `PREVIEW_MAX_LENGTH` | `255` | Cap for `Recommendation_Preview__c`; longer text is truncated to `length - 3` and suffixed with `...` |

Tuning the policy means changing one of these values and redeploying the class.

---

## Control Flow

`evaluate(Id inventoryPositionId, Boolean confirm)` runs eight steps:

```
  1. Load target position with full relational context
        |
        v
  2. Compliance gate: Schedule II ?
        |                                    \
        | no                                   \ yes
        v                                       v
  3. Find candidate sources (selector)    write Blocked Transfer_Log__c
        |                                       |
        v                                       v
  4. selectBestSource (eligibility filters)  return DEA Form 222 message
        |
        v
  5. bestSource == null ?
        |                                    \
        | no                                   \ yes
        v                                       v
  6. calculateTransferQty                   return distributor-fallback message
        |
        v
  7. confirm == false ?                yes -> buildRecommendation
        |                                       writes Recommendation__c +
        | no                                    Recommendation_Preview__c
        v                                       returns "Shall I proceed?"
  8. executeTransfer (atomic DML + log)
```

Step 1 is the only SOQL on the target. Step 3 is the only SOQL on candidate sources. Steps 7 and 8 are the only DML paths. Everything else is in-memory logic.

---

## Step 1 — Load Target

`InventoryPositionSelector.getById()` runs one SOQL query with the full relational graph needed for every downstream decision:

- `Inventory_Position__c` core fields (`Quantity__c`, `Safety_Stock__c`, `Expiry_Date__c`, `Status__c`, `Recommendation__c`)
- `Store__r` (`Name`, `Latitude__c`, `Longitude__c`, `Cold_Chain_Capable__c`, `DEA_Registration__c`, `Is_Active__c`)
- `Medication__r` (`Name`, `DEA_Schedule__c`, `Cold_Chain_Required__c`)

Query uses `WITH SECURITY_ENFORCED`. If the row isn't found, the selector throws `QueryException("Inventory Position not found: <id>")`, which the service catches and converts into a graceful "Unable to locate Inventory Position" `uhText` so the agent never surfaces a raw stack trace.

---

## Step 2 — Compliance Gate

```apex
private static Boolean isScheduleII(Inventory_Position__c inv) {
    return inv.Medication__r.DEA_Schedule__c == DEA_SCHEDULE_II;
}
```

If true:

1. `logComplianceBlock(target)` writes a `Transfer_Log__c` with:
   - `Target_Store__c` = the requesting store
   - `Source_Store__c` = `null` (no source was searched)
   - `Quantity_Transferred__c` = `0`
   - `Transfer_Status__c` = `'Blocked'`
   - `Notes__c` = `"COMPLIANCE BLOCK: DEA Schedule II - <medication name>. DEA Form 222 required. Automated transfer denied by Agentforce Grid."`
2. Return a `TransferResult(false, ...)` whose `uhText` instructs the user to contact the DEA compliance officer for a manual Form 222 transfer.

The gate runs **before** any source query, so a Schedule II request never causes SOQL on candidate sources. This is intentional — it keeps the audit log clean and avoids leaking source store availability for controlled substances.

---

## Step 3 — Find Candidates

`InventoryPositionSelector.findSurplusSources(medicationId, excludeStoreId, minimumSurplus)`:

```sql
SELECT ...full graph...
FROM   Inventory_Position__c
WHERE  Medication__c = :medicationId
AND    Store__c     != :excludeStoreId
AND    Quantity__c  >  :minQty
AND    Store__r.Is_Active__c = true
WITH   SECURITY_ENFORCED
ORDER BY Quantity__c DESC
```

`minQty` is passed as `target.Safety_Stock__c + 1`, so candidates must have **strictly more** than the target's safety stock — pulling from a candidate that's already at its own threshold is excluded by the SOQL `Quantity__c > minQty`.

> Note: this `minQty` is checked against the **target's** safety stock, not the candidate's. The candidate's own safety stock is enforced inside `selectBestSource()` indirectly via `calculateTransferQty()`, which only takes 50% of the candidate's surplus above its own threshold.

---

## Step 4 — Select Best Source

`selectBestSource()` walks the candidate list (already sorted by `Quantity__c DESC`) and applies three eligibility filters in order:

1. **Cold-chain**: if `target.Medication__r.Cold_Chain_Required__c` is `true`, then `candidate.Store__r.Cold_Chain_Capable__c` must also be `true`.
2. **DEA registration**: `candidate.Store__r.DEA_Registration__c` must be non-blank.
3. **Expiry threshold**: if `candidate.Expiry_Date__c` is set, `Date.today().daysBetween(candidate.Expiry_Date__c)` must be `>= MIN_DAYS_TO_EXPIRY` (30 days).

The first candidate to pass all three is returned. Because the list is pre-sorted by quantity, "first eligible" equals "highest-stock eligible source".

If no candidate passes, the method returns `null` and the service returns the distributor-fallback message.

---

## Step 6 — Calculate Quantity

```apex
private static Integer calculateTransferQty(
    Inventory_Position__c target,
    Inventory_Position__c source
) {
    Integer sourceSurplus = (Integer)(source.Quantity__c - source.Safety_Stock__c);
    Integer targetNeed    = (Integer)(target.Safety_Stock__c - target.Quantity__c);
    Integer proposed      = (Integer)(sourceSurplus * TRANSFER_BUFFER_PCT / 100.0);
    return Math.min(proposed, targetNeed);
}
```

**The cap matters.** Without `Math.min`, a generous source could over-transfer beyond the target's actual need, leaving the source under its own buffer and the target over-stocked. The cap guarantees the target receives exactly enough to reach its safety stock — no more, no less.

### Worked Example 1 — Target needs less than 50% of source surplus

- Source: `Quantity__c = 200`, `Safety_Stock__c = 50` → surplus 150
- Target: `Quantity__c = 0`, `Safety_Stock__c = 50` → need 50
- Proposed: `150 × 50 / 100 = 75`
- Result: `min(75, 50) = 50`

Target reaches safety stock. Source retains a 100-unit buffer above its own.

### Worked Example 2 — Target need exceeds 50% of source surplus

- Source: `Quantity__c = 100`, `Safety_Stock__c = 40` → surplus 60
- Target: `Quantity__c = 0`, `Safety_Stock__c = 100` → need 100
- Proposed: `60 × 50 / 100 = 30`
- Result: `min(30, 100) = 30`

Source contributes 30 units (its half-surplus), and the target gets only partial replenishment. The 50% buffer protects the source from being drained even when the target is desperate. The remaining target need has to be filled from another source via a separate evaluation cycle, or via the distributor.

### Worked Example 3 — Source at exactly safety stock

- Source: `Quantity__c = 51`, `Safety_Stock__c = 50` → surplus 1
- Target: `Quantity__c = 0`, `Safety_Stock__c = 50` → need 50

This source is already excluded by the SOQL filter `Quantity__c > target.Safety_Stock__c + 1`, since 51 is not greater than 51. So `selectBestSource()` never sees this row.

---

## Step 7 — Dry-Run (`buildRecommendation`)

On `confirm = false`, the service writes both recommendation fields and returns a `uhText` that ends with *"Shall I proceed with this transfer?"*. The agent surfaces this text and waits for user confirmation.

Before writing, `buildRecommendation()` checks both `isUpdateable()` on the object and on each individual field:

```apex
if (Schema.sObjectType.Inventory_Position__c.isUpdateable()
    && Schema.sObjectType.Inventory_Position__c.fields.Recommendation__c.isUpdateable()
    && Schema.sObjectType.Inventory_Position__c.fields.Recommendation_Preview__c.isUpdateable()
) {
    update new Inventory_Position__c(...);
}
```

If FLS denies any of these, no DML occurs and the dry-run still returns the `uhText` to the agent — the recommendation just isn't persisted to the record.

---

## Step 8 — Execute (`executeTransfer`)

The execution path is wrapped in `try` / `catch` with a `Savepoint`:

```apex
Savepoint sp = Database.setSavepoint();
try {
    // CRUD checks: isUpdateable on Inventory_Position__c, isCreateable on Transfer_Log__c
    // Build sourceUpdate (deduct), targetUpdate (add + completion preview)
    // Build Transfer_Log__c with all fields including Notes__c
    SObjectAccessDecision decision = Security.stripInaccessible(
        AccessType.UPDATABLE,
        new List<SObject>{ sourceUpdate, targetUpdate }
    );
    update decision.getRecords();
    insert log;
    return new TransferResult(true, ...);
} catch (Exception ex) {
    Database.rollback(sp);
    return new TransferResult(false, "Transfer failed and was fully rolled back. ...");
}
```

Two things to note:

1. **CRUD checks throw `SecurityException` early**, before any DML. The catch block converts them into a clean `uhText` so the agent surfaces a permission-denied message instead of a stack trace.
2. **`stripInaccessible` is applied to the update list only.** The `Transfer_Log__c` insert is gated by an explicit `isCreateable()` check earlier; we want the audit record's full content to be written without FLS stripping.

---

## What Happens to `Recommendation__c` After Execution

`executeTransfer()` overwrites `Recommendation_Preview__c` with the completion message:

> *"Transfer completed: N units from <source name>. See Transfer Log for details."*

But `Recommendation__c` (the Long Text Area) is **not** cleared. The Grid column reads `Recommendation_Preview__c`, so the user sees the post-execution state. But anyone looking at the record's detail view will still see the pre-execution dry-run text in `Recommendation__c`.

This is documented in the README's **Known Gaps** section as a minor cleanup item.
