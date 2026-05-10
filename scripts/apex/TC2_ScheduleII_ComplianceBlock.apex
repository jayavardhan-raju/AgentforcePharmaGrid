// ==============================================================================
// TC2 -- AGENTFORCE GRID -- "Schedule II Compliance Hard Stop"
//
// Adderall XR 30mg (DEA Schedule II) is critical at CVS Downtown SF. Even though
// CVS San Jose Central holds 100 surplus units with a valid DEA registration,
// the service must intercept this request at the compliance gate. No source
// search is performed. A "Blocked" Transfer_Log__c is written for the DEA audit
// trail with Source_Store__c = null and Quantity_Transferred__c = 0.
//
// What this script creates and what you'll see:
//   * 2 Pharmacy_Store__c rows (target + a candidate that should NEVER be selected)
//   * 1 Medication__c (Adderall XR 30mg, DEA Schedule II)
//   * 2 Inventory_Position__c rows
//   * Calls evaluate(confirm=false) -> returns DEA Form 222 message + writes Blocked log
//   * No call to evaluate(confirm=true) -- the agent should not even prompt for confirmation
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------

Set<String> demoStoreNames = new Set<String>{ 'TC2 Target SF Downtown', 'TC2 Source SJ Central' };
Set<String> demoMedNames   = new Set<String>{ 'TC2 Adderall XR 30mg' };

List<Transfer_Log__c> oldLogs = [
    SELECT Id FROM Transfer_Log__c
    WHERE Inventory_Position__r.Store__r.Name IN :demoStoreNames
       OR Target_Store__r.Name              IN :demoStoreNames
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

System.debug('[OK] Cleanup complete. Building TC2 scenario.');

// --- STANDARD OBJECT RECORDS --------------------------------------------------
// Both stores are valid candidates on every dimension (DEA registration, active,
// cold-chain doesn't matter for this med). The compliance gate must still block.

Pharmacy_Store__c target = new Pharmacy_Store__c(
    Name                  = 'TC2 Target SF Downtown',
    District__c           = 'District 1 - Bay Area',
    Latitude__c           = 37.7749,
    Longitude__c          = -122.4194,
    Cold_Chain_Capable__c = true,
    DEA_Registration__c   = 'DEA-TC2-TGT-001',
    Is_Active__c          = true
);
Pharmacy_Store__c source = new Pharmacy_Store__c(
    Name                  = 'TC2 Source SJ Central',
    District__c           = 'District 2 - South Bay',
    Latitude__c           = 37.3382,
    Longitude__c          = -121.8863,
    Cold_Chain_Capable__c = true,
    DEA_Registration__c   = 'DEA-TC2-SRC-002',
    Is_Active__c          = true
);
insert new List<Pharmacy_Store__c>{ target, source };
System.debug('[OK] Created stores: target=' + target.Id + ', source=' + source.Id);

// Schedule II controlled substance -- this is what triggers the hard stop
Medication__c med = new Medication__c(
    Name                   = 'TC2 Adderall XR 30mg',
    NDC__c                 = '54092-0391-TC2',
    DEA_Schedule__c        = 'II',
    Cold_Chain_Required__c = false
);
insert med;
System.debug('[OK] Created Schedule II medication: ' + med.Id);

// --- INVENTORY POSITIONS ------------------------------------------------------
// Target qty=5 (well below safety 30 -> Status__c=LOW, Status_Color__c=ORANGE)
// Source qty=100 (healthy surplus that the service must NOT search)

Inventory_Position__c targetInv = new Inventory_Position__c(
    Store__c          = target.Id,
    Medication__c     = med.Id,
    Quantity__c       = 5,
    Safety_Stock__c   = 30,
    Expiry_Date__c    = Date.today().addDays(180),
    Recommendation__c = ''
);
Inventory_Position__c sourceInv = new Inventory_Position__c(
    Store__c          = source.Id,
    Medication__c     = med.Id,
    Quantity__c       = 100,
    Safety_Stock__c   = 20,
    Expiry_Date__c    = Date.today().addDays(150),
    Recommendation__c = ''
);
insert new List<Inventory_Position__c>{ targetInv, sourceInv };
System.debug('[OK] Created Inventory_Position__c: target=' + targetInv.Id + ', source=' + sourceInv.Id);

// Snapshot pre-call inventory state -- must be unchanged after the call
Decimal sourceQtyBefore = sourceInv.Quantity__c;
Decimal targetQtyBefore = targetInv.Quantity__c;
Integer logCountBefore  = [SELECT COUNT() FROM Transfer_Log__c WHERE Target_Store__c = :target.Id];

// --- INVOKE SERVICE: COMPLIANCE BLOCK -----------------------------------------
// The compliance gate is the FIRST thing evaluate() checks after loading the
// target. confirm flag value doesn't matter -- the gate runs before the branch.

System.debug('[VERIFY] Calling InterStoreTransferService.evaluate(targetId, false)...');
InterStoreTransferService.TransferResult result =
    InterStoreTransferService.evaluate(targetInv.Id, false);

System.debug('[OK] result.success      = ' + result.success      + ' (expected false)');
System.debug('[OK] result.transferLogId= ' + result.transferLogId + ' (expected null)');
System.debug('[OK] result.recommendedQty=' + result.recommendedQty+ ' (expected null)');
System.debug('[OK] result.sourceStoreId= ' + result.sourceStoreId + ' (expected null -- no source was searched)');
System.debug('[OK] result.uhText       = ' + result.uhText);

// --- FINAL VERIFICATION -------------------------------------------------------

if (result.success != false) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Schedule II should have been blocked. success=' + result.success);
    return;
}
if (!result.uhText.contains('Schedule II') || !result.uhText.contains('DEA Form 222')) {
    System.debug(LoggingLevel.ERROR, '[ERROR] uhText missing expected DEA Form 222 message: ' + result.uhText);
    return;
}

// Verify inventory unchanged (no source search, no DML on positions)
Inventory_Position__c sourceCheck = [SELECT Quantity__c FROM Inventory_Position__c WHERE Id = :sourceInv.Id];
Inventory_Position__c targetCheck = [SELECT Quantity__c, Recommendation__c FROM Inventory_Position__c WHERE Id = :targetInv.Id];
if (sourceCheck.Quantity__c != sourceQtyBefore || targetCheck.Quantity__c != targetQtyBefore) {
    System.debug(LoggingLevel.ERROR,
        '[ERROR] Inventory was mutated despite Schedule II block. source=' + sourceCheck.Quantity__c
        + ' target=' + targetCheck.Quantity__c);
    return;
}
System.debug('[OK] Inventory unchanged: target=' + targetCheck.Quantity__c + ' source=' + sourceCheck.Quantity__c);

// Recommendation__c must NOT be written on Schedule II (compliance gate fires before buildRecommendation)
if (String.isNotBlank(targetCheck.Recommendation__c)) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Recommendation__c was written despite Schedule II block: ' + targetCheck.Recommendation__c);
    return;
}
System.debug('[OK] Recommendation__c not written (correct -- compliance gate is before recommendation step)');

// Verify Blocked Transfer_Log__c written
List<Transfer_Log__c> blockedLogs = [
    SELECT Id, Source_Store__c, Target_Store__c, Quantity_Transferred__c,
           Transfer_Status__c, Notes__c, Medication__r.Name, Inventory_Position__c
    FROM   Transfer_Log__c
    WHERE  Target_Store__c     = :target.Id
    AND    Transfer_Status__c  = 'Blocked'
    AND    Inventory_Position__c = :targetInv.Id
];
System.debug('[VERIFY] Blocked Transfer_Log__c rows found: ' + blockedLogs.size() + ' (expected 1)');
if (blockedLogs.size() != 1) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Expected exactly 1 Blocked Transfer_Log__c, got ' + blockedLogs.size());
    return;
}
Transfer_Log__c log = blockedLogs[0];
System.debug('[VERIFY] Log.Source_Store__c       = ' + log.Source_Store__c + ' (expected null)');
System.debug('[VERIFY] Log.Target_Store__c       = ' + log.Target_Store__c);
System.debug('[VERIFY] Log.Quantity_Transferred__c = ' + log.Quantity_Transferred__c + ' (expected 0)');
System.debug('[VERIFY] Log.Medication__r.Name    = ' + log.Medication__r.Name);
System.debug('[VERIFY] Log.Notes__c              = ' + log.Notes__c);

if (log.Source_Store__c != null) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Source_Store__c should be null on Schedule II block');
} else if (log.Quantity_Transferred__c != 0) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Quantity_Transferred__c should be 0 on Schedule II block');
} else {
    System.debug('[OK] All Schedule II block assertions passed for TC2');
}

System.debug('[TC2 COMPLETE]');
System.debug('Navigate to: /lightning/r/Inventory_Position__c/' + targetInv.Id + '/view');
System.debug('Then check Transfer Logs related list -> 1 Blocked entry with no Source Store');
