// ==============================================================================
// TC3 -- AGENTFORCE GRID -- "Distributor Fallback (Near-Expiry Exclusion)"
//
// Ozempic 1mg (cold-chain required) is critical at CVS San Jose Central. Two
// stores have surplus -- but each fails a different eligibility filter:
//   * CVS Downtown SF: cold-chain capable, valid DEA reg, but stock expires
//     in 15 days (< MIN_DAYS_TO_EXPIRY of 30).
//   * CVS Eastside Oakland: NOT cold-chain capable (med requires it).
// selectBestSource() filters both out and returns null, so the service returns
// the distributor-fallback uhText instructing the user to place an emergency
// order with the primary distributor.
//
// What this script creates and what you'll see:
//   * 3 Pharmacy_Store__c rows (target + two ineligible candidates)
//   * 1 Medication__c (Ozempic 1mg, cold-chain required)
//   * 3 Inventory_Position__c rows
//   * Calls evaluate(confirm=false) -> returns "No suitable source store" + distributor advice
//   * No Transfer_Log__c is written (no source identified, no compliance block)
//   * No Recommendation__c is written
// ==============================================================================

// --- CLEANUP ------------------------------------------------------------------

Set<String> demoStoreNames = new Set<String>{
    'TC3 Target SJ Central',
    'TC3 Source SF Downtown NearExpiry',
    'TC3 Source Oakland NoColdChain'
};
Set<String> demoMedNames = new Set<String>{ 'TC3 Ozempic 1mg' };

List<Transfer_Log__c> oldLogs = [
    SELECT Id FROM Transfer_Log__c
    WHERE Inventory_Position__r.Store__r.Name IN :demoStoreNames
       OR Source_Store__r.Name              IN :demoStoreNames
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

System.debug('[OK] Cleanup complete. Building TC3 scenario.');

// --- STANDARD OBJECT RECORDS --------------------------------------------------

Pharmacy_Store__c target = new Pharmacy_Store__c(
    Name                  = 'TC3 Target SJ Central',
    District__c           = 'District 2 - South Bay',
    Latitude__c           = 37.3382,
    Longitude__c          = -121.8863,
    Cold_Chain_Capable__c = true,                  // target itself is cold-chain capable
    DEA_Registration__c   = 'DEA-TC3-TGT-001',
    Is_Active__c          = true
);

// Candidate 1: cold-chain OK, DEA reg OK, but stock expires too soon
Pharmacy_Store__c sourceNearExpiry = new Pharmacy_Store__c(
    Name                  = 'TC3 Source SF Downtown NearExpiry',
    District__c           = 'District 1 - Bay Area',
    Latitude__c           = 37.7749,
    Longitude__c          = -122.4194,
    Cold_Chain_Capable__c = true,
    DEA_Registration__c   = 'DEA-TC3-SRC1-002',
    Is_Active__c          = true
);

// Candidate 2: NOT cold-chain capable -> filtered out for cold-chain medication
Pharmacy_Store__c sourceNoColdChain = new Pharmacy_Store__c(
    Name                  = 'TC3 Source Oakland NoColdChain',
    District__c           = 'District 1 - Bay Area',
    Latitude__c           = 37.8044,
    Longitude__c          = -122.2712,
    Cold_Chain_Capable__c = false,                 // <-- the disqualifier
    DEA_Registration__c   = 'DEA-TC3-SRC2-003',
    Is_Active__c          = true
);
insert new List<Pharmacy_Store__c>{ target, sourceNearExpiry, sourceNoColdChain };
System.debug('[OK] Created stores: target=' + target.Id
    + ', sourceNearExpiry=' + sourceNearExpiry.Id
    + ', sourceNoColdChain=' + sourceNoColdChain.Id);

Medication__c med = new Medication__c(
    Name                   = 'TC3 Ozempic 1mg',
    NDC__c                 = '00169-4132-TC3',
    DEA_Schedule__c        = 'None',
    Cold_Chain_Required__c = true                 // <-- this is what disqualifies sourceNoColdChain
);
insert med;
System.debug('[OK] Created cold-chain medication: ' + med.Id);

// --- INVENTORY POSITIONS ------------------------------------------------------
// Target qty=5 (LOW vs safety 40)
// sourceNearExpiry qty=100 -- WOULD be selected (highest qty, first in ORDER BY DESC)
//                            but expires in 15 days < MIN_DAYS_TO_EXPIRY (30)
// sourceNoColdChain qty=80 -- filtered for cold-chain mismatch

Inventory_Position__c targetInv = new Inventory_Position__c(
    Store__c          = target.Id,
    Medication__c     = med.Id,
    Quantity__c       = 5,
    Safety_Stock__c   = 40,
    Expiry_Date__c    = Date.today().addDays(180),
    Recommendation__c = ''
);
Inventory_Position__c invNearExpiry = new Inventory_Position__c(
    Store__c          = sourceNearExpiry.Id,
    Medication__c     = med.Id,
    Quantity__c       = 100,
    Safety_Stock__c   = 20,
    Expiry_Date__c    = Date.today().addDays(15),  // < 30 -> excluded
    Recommendation__c = ''
);
Inventory_Position__c invNoColdChain = new Inventory_Position__c(
    Store__c          = sourceNoColdChain.Id,
    Medication__c     = med.Id,
    Quantity__c       = 80,
    Safety_Stock__c   = 20,
    Expiry_Date__c    = Date.today().addDays(120),
    Recommendation__c = ''
);
insert new List<Inventory_Position__c>{ targetInv, invNearExpiry, invNoColdChain };
System.debug('[OK] Created Inventory_Position__c: target=' + targetInv.Id
    + ', invNearExpiry=' + invNearExpiry.Id
    + ', invNoColdChain=' + invNoColdChain.Id);

// Snapshot pre-call state
Decimal nearExpiryQtyBefore = invNearExpiry.Quantity__c;
Decimal noColdChainQtyBefore = invNoColdChain.Quantity__c;
Decimal targetQtyBefore = targetInv.Quantity__c;

// --- INVOKE SERVICE: DISTRIBUTOR FALLBACK -------------------------------------

System.debug('[VERIFY] Calling InterStoreTransferService.evaluate(targetId, false)...');
InterStoreTransferService.TransferResult result =
    InterStoreTransferService.evaluate(targetInv.Id, false);

System.debug('[OK] result.success         = ' + result.success         + ' (expected false)');
System.debug('[OK] result.sourceStoreId   = ' + result.sourceStoreId   + ' (expected null)');
System.debug('[OK] result.recommendedQty  = ' + result.recommendedQty  + ' (expected null)');
System.debug('[OK] result.transferLogId   = ' + result.transferLogId   + ' (expected null)');
System.debug('[OK] result.uhText          = ' + result.uhText);

// --- FINAL VERIFICATION -------------------------------------------------------

if (result.success != false) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Expected fallback (success=false), got success=' + result.success);
    return;
}
if (!result.uhText.contains('No suitable source store') || !result.uhText.contains('emergency order')) {
    System.debug(LoggingLevel.ERROR, '[ERROR] uhText missing expected distributor-fallback phrasing: ' + result.uhText);
    return;
}
System.debug('[OK] uhText contains expected distributor-fallback phrasing');

// Verify all inventory rows are unchanged
Map<Id, Inventory_Position__c> after = new Map<Id, Inventory_Position__c>([
    SELECT Id, Quantity__c, Recommendation__c, Recommendation_Preview__c
    FROM   Inventory_Position__c
    WHERE  Id IN (:targetInv.Id, :invNearExpiry.Id, :invNoColdChain.Id)
]);
if (after.get(invNearExpiry.Id).Quantity__c != nearExpiryQtyBefore
    || after.get(invNoColdChain.Id).Quantity__c != noColdChainQtyBefore
    || after.get(targetInv.Id).Quantity__c != targetQtyBefore) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Inventory was mutated despite distributor-fallback path');
    return;
}
System.debug('[OK] All inventory quantities unchanged');

// On the distributor-fallback path, no Recommendation should be written either
if (String.isNotBlank(after.get(targetInv.Id).Recommendation__c)) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Recommendation__c was written despite no eligible source: '
        + after.get(targetInv.Id).Recommendation__c);
    return;
}
System.debug('[OK] Recommendation__c not written (correct -- buildRecommendation is only called when a source is found)');

// And no Transfer_Log__c (no compliance block, no execution)
Integer logCount = [
    SELECT COUNT() FROM Transfer_Log__c WHERE Inventory_Position__c = :targetInv.Id
];
if (logCount != 0) {
    System.debug(LoggingLevel.ERROR, '[ERROR] Expected 0 Transfer_Log__c rows on distributor-fallback, got ' + logCount);
    return;
}
System.debug('[OK] No Transfer_Log__c written (correct)');

System.debug('[OK] All distributor-fallback assertions passed for TC3');

System.debug('[TC3 COMPLETE]');
System.debug('Navigate to: /lightning/r/Inventory_Position__c/' + targetInv.Id + '/view');
System.debug('Note: target Status_Color__c is ORANGE (LOW). Recommendation_Preview__c is blank.');
System.debug('In the agent conversation the user would see the distributor-fallback uhText.');
