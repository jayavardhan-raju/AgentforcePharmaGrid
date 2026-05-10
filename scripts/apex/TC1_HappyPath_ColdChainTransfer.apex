// ==============================================================================
// TC1 -- AGENTFORCE GRID -- "Happy Path: Cold-Chain Transfer"
//
// Mounjaro 5mg is critical at CVS Downtown SF (cold-chain target). CVS Westside
// SF holds 200 units (cold-chain capable, valid DEA registration, 90 days to
// expiry). The service should select Westside as the source, propose a transfer
// of exactly 50 units (capped at target need, since 50% of source surplus = 75
// would over-transfer), and on confirmation execute the move atomically with a
// Completed Transfer_Log__c audit record.
//
// What this script creates and what you'll see:
//   * 2 Pharmacy_Store__c rows (target + source, both cold-chain capable)
//   * 1 Medication__c (Mounjaro 5mg, cold-chain required, no DEA schedule)
//   * 2 Inventory_Position__c rows seeded with critical/surplus state
//   * Calls evaluate(confirm=false) -> Recommendation__c populated
//   * Calls evaluate(confirm=true)  -> source/target qty updated, Transfer_Log__c written
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------
// Delete in FK-safe order: Transfer_Log__c -> Inventory_Position__c -> Medication__c -> Pharmacy_Store__c
// We scope the delete by the unique demo names this script uses, so re-running
// is safe and won't disturb other demo data in the org.

Set<String> demoStoreNames = new Set<String>{ 'TC1 Target SF Downtown', 'TC1 Source SF Westside' };
Set<String> demoMedNames   = new Set<String>{ 'TC1 Mounjaro 5mg' };

List<Transfer_Log__c> oldLogs = [
    SELECT Id FROM Transfer_Log__c
    WHERE Inventory_Position__r.Store__r.Name IN :demoStoreNames
       OR Source_Store__r.Name              IN :demoStoreNames
];
if (!oldLogs.isEmpty()) { delete oldLogs; System.debug('[OK] Deleted ' + oldLogs.size() + ' old Transfer_Log__c rows'); }

List<Inventory_Position__c> oldInv = [
    SELECT Id FROM Inventory_Position__c
    WHERE Store__r.Name IN :demoStoreNames OR Medication__r.Name IN :demoMedNames
];
if (!oldInv.isEmpty()) { delete oldInv; System.debug('[OK] Deleted ' + oldInv.size() + ' old Inventory_Position__c rows'); }

List<Medication__c> oldMeds = [SELECT Id FROM Medication__c WHERE Name IN :demoMedNames];
if (!oldMeds.isEmpty()) { delete oldMeds; System.debug('[OK] Deleted ' + oldMeds.size() + ' old Medication__c rows'); }

List<Pharmacy_Store__c> oldStores = [SELECT Id FROM Pharmacy_Store__c WHERE Name IN :demoStoreNames];
if (!oldStores.isEmpty()) { delete oldStores; System.debug('[OK] Deleted ' + oldStores.size() + ' old Pharmacy_Store__c rows'); }

System.debug('[OK] Cleanup complete. Building TC1 scenario.');

// --- STANDARD OBJECT RECORDS --------------------------------------------------
// Two cold-chain-capable Bay Area stores. Both have non-blank DEA registration
// and Is_Active__c = true. Lat/lng pinned to real San Francisco coordinates.

Pharmacy_Store__c target = new Pharmacy_Store__c(
    Name                  = 'TC1 Target SF Downtown',
    District__c           = 'District 1 - Bay Area',
    Latitude__c           = 37.7749,
    Longitude__c          = -122.4194,
    Cold_Chain_Capable__c = true,
    DEA_Registration__c   = 'DEA-TC1-TGT-001',
    Is_Active__c          = true
);
Pharmacy_Store__c source = new Pharmacy_Store__c(
    Name                  = 'TC1 Source SF Westside',
    District__c           = 'District 1 - Bay Area',
    Latitude__c           = 37.7599,
    Longitude__c          = -122.5107,
    Cold_Chain_Capable__c = true,
    DEA_Registration__c   = 'DEA-TC1-SRC-002',
    Is_Active__c          = true
);
insert new List<Pharmacy_Store__c>{ target, source };
System.debug('[OK] Created stores: target=' + target.Id + ', source=' + source.Id);

Medication__c med = new Medication__c(
    Name                   = 'TC1 Mounjaro 5mg',
    NDC__c                 = '00002-1523-TC1',
    DEA_Schedule__c        = 'None',
    Cold_Chain_Required__c = true
);
insert med;
System.debug('[OK] Created medication: ' + med.Id);

// --- INVENTORY POSITIONS ------------------------------------------------------
// Target: critical (qty 0, safety 50)
// Source: healthy surplus (qty 200, safety 50, expiry +90d -- well beyond the 30-day threshold)

Inventory_Position__c targetInv = new Inventory_Position__c(
    Store__c          = target.Id,
    Medication__c     = med.Id,
    Quantity__c       = 0,
    Safety_Stock__c   = 50,
    Expiry_Date__c    = Date.today().addDays(120),
    Recommendation__c = ''
);
Inventory_Position__c sourceInv = new Inventory_Position__c(
    Store__c          = source.Id,
    Medication__c     = med.Id,
    Quantity__c       = 200,
    Safety_Stock__c   = 50,
    Expiry_Date__c    = Date.today().addDays(90),
    Recommendation__c = ''
);
insert new List<Inventory_Position__c>{ targetInv, sourceInv };
System.debug('[OK] Created Inventory_Position__c: target=' + targetInv.Id + ', source=' + sourceInv.Id);

// --- INVOKE SERVICE: DRY-RUN --------------------------------------------------
// confirm = false -> writes Recommendation__c + Recommendation_Preview__c on target,
// returns uhText ending in "Shall I proceed with this transfer?"

System.debug('[VERIFY] Calling InterStoreTransferService.evaluate(targetId, false)...');
InterStoreTransferService.TransferResult dryRun =
    InterStoreTransferService.evaluate(targetInv.Id, false);

System.debug('[OK] dryRun.success         = ' + dryRun.success);
System.debug('[OK] dryRun.recommendedQty  = ' + dryRun.recommendedQty);
System.debug('[OK] dryRun.sourceStoreName = ' + dryRun.sourceStoreName);
System.debug('[OK] dryRun.uhText          = ' + dryRun.uhText);

if (!dryRun.success || dryRun.recommendedQty != 50) {
    System.debug(LoggingLevel.ERROR,
        '[ERROR] Expected dry-run success with recommendedQty=50, got success='
        + dryRun.success + ' qty=' + dryRun.recommendedQty);
    return;
}

// Verify the Recommendation_Preview__c was written and is <=255 chars
Inventory_Position__c afterDryRun = [
    SELECT Recommendation__c, Recommendation_Preview__c, Status__c, Status_Color__c
    FROM   Inventory_Position__c
    WHERE  Id = :targetInv.Id
];
System.debug('[VERIFY] Recommendation__c length        = ' + (afterDryRun.Recommendation__c == null ? 0 : afterDryRun.Recommendation__c.length()));
System.debug('[VERIFY] Recommendation_Preview__c length= ' + (afterDryRun.Recommendation_Preview__c == null ? 0 : afterDryRun.Recommendation_Preview__c.length()));
System.debug('[VERIFY] Status__c                       = ' + afterDryRun.Status__c + ' (' + afterDryRun.Status_Color__c + ')');

// --- INVOKE SERVICE: EXECUTE --------------------------------------------------
// confirm = true -> deducts 50 from source, adds 50 to target, inserts Completed Transfer_Log__c

System.debug('[VERIFY] Calling InterStoreTransferService.evaluate(targetId, true)...');
InterStoreTransferService.TransferResult execResult =
    InterStoreTransferService.evaluate(targetInv.Id, true);

System.debug('[OK] execResult.success         = ' + execResult.success);
System.debug('[OK] execResult.transferLogId   = ' + execResult.transferLogId);
System.debug('[OK] execResult.recommendedQty  = ' + execResult.recommendedQty);
System.debug('[OK] execResult.uhText          = ' + execResult.uhText);

if (!execResult.success || execResult.transferLogId == null) {
    System.debug(LoggingLevel.ERROR,
        '[ERROR] Expected execution success with non-null transferLogId, got success='
        + execResult.success + ' logId=' + execResult.transferLogId);
    return;
}

// --- FINAL VERIFICATION -------------------------------------------------------
// Re-query target, source, and the Transfer_Log__c to confirm post-execution state.

Inventory_Position__c targetAfter = [
    SELECT Quantity__c, Safety_Stock__c, Status__c, Recommendation_Preview__c
    FROM   Inventory_Position__c WHERE Id = :targetInv.Id
];
Inventory_Position__c sourceAfter = [
    SELECT Quantity__c, Safety_Stock__c, Status__c
    FROM   Inventory_Position__c WHERE Id = :sourceInv.Id
];
Transfer_Log__c log = [
    SELECT Id, Source_Store__r.Name, Target_Store__r.Name, Medication__r.Name,
           Quantity_Transferred__c, Transfer_Status__c, Transfer_Date__c, Notes__c
    FROM   Transfer_Log__c WHERE Id = :execResult.transferLogId
];

System.debug('[VERIFY] Target qty:  ' + targetAfter.Quantity__c + ' (was 0, expected 50). Status=' + targetAfter.Status__c);
System.debug('[VERIFY] Source qty:  ' + sourceAfter.Quantity__c + ' (was 200, expected 150). Status=' + sourceAfter.Status__c);
System.debug('[VERIFY] Target preview after exec: ' + targetAfter.Recommendation_Preview__c);
System.debug('[VERIFY] Transfer_Log__c: ' + log.Source_Store__r.Name + ' -> ' + log.Target_Store__r.Name);
System.debug('[VERIFY]   Medication: ' + log.Medication__r.Name);
System.debug('[VERIFY]   Qty:        ' + log.Quantity_Transferred__c);
System.debug('[VERIFY]   Status:     ' + log.Transfer_Status__c);
System.debug('[VERIFY]   Date:       ' + log.Transfer_Date__c);
System.debug('[VERIFY]   Notes:      ' + log.Notes__c);

if (targetAfter.Quantity__c == 50 && sourceAfter.Quantity__c == 150 && log.Transfer_Status__c == 'Completed') {
    System.debug('[OK] All assertions passed for TC1');
} else {
    System.debug(LoggingLevel.ERROR, '[ERROR] Post-execution state did not match expected values');
}

System.debug('[TC1 COMPLETE]');
System.debug('Navigate to: /lightning/r/Inventory_Position__c/' + targetInv.Id + '/view');
