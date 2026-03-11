/**
 * ============================================================================
 * Script 3 of 3: Create Inventory Position Records
 * ============================================================================
 * 
 * Run via: sf apex run --file scripts/data/3_Create_Inventory_Positions.apex --target-org <alias>
 * 
 * Creates inventory positions that demonstrate all transfer scenarios:
 *   - OUT_OF_STOCK and LOW positions at target stores (transfer candidates)
 *   - HEALTHY surplus positions at source stores (transfer donors)
 *   - Near-expiry stock (filtered out by 30-day threshold)
 *   - Schedule II medication positions (compliance hard stop)
 *   - Cold-chain medication positions (source capability filtering)
 * 
 * IMPORTANT: Run Script 1 (Pharmacy Stores) and Script 2 (Medications)
 *            before running this script. This script queries those records
 *            by Name to establish the lookup relationships.
 * ============================================================================
 */

// ── Query Stores (created by Script 1) ───────────────────────────────────
Map<String, Id> storeMap = new Map<String, Id>();
for (Pharmacy_Store__c s : [
    SELECT Id, Name FROM Pharmacy_Store__c
    WHERE Name IN (
        'CVS Downtown SF',
        'CVS Westside SF',
        'CVS Eastside Oakland',
        'CVS San Jose Central',
        'CVS Sunnyvale'
    )
]) {
    storeMap.put(s.Name, s.Id);
}

// ── Query Medications (created by Script 2) ──────────────────────────────
Map<String, Id> medMap = new Map<String, Id>();
for (Medication__c m : [
    SELECT Id, Name FROM Medication__c
    WHERE Name IN (
        'Mounjaro 5mg',
        'Ozempic 1mg',
        'Adderall XR 30mg',
        'Xanax 0.5mg',
        'Lisinopril 10mg',
        'Amoxicillin 500mg'
    )
]) {
    medMap.put(m.Name, m.Id);
}

// ── Validate prerequisites ───────────────────────────────────────────────
System.assert(!storeMap.isEmpty(), 'ERROR: No stores found. Run Script 1 first.');
System.assert(!medMap.isEmpty(),   'ERROR: No medications found. Run Script 2 first.');

System.debug('Found ' + storeMap.size() + ' stores and ' + medMap.size() + ' medications.');

List<Inventory_Position__c> positions = new List<Inventory_Position__c>();

// =========================================================================
// Scenario 1: Mounjaro 5mg — Happy Path Transfer (Cold-Chain Required)
// =========================================================================
// CVS Downtown SF: OUT_OF_STOCK — this is the target row ops user will click
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(120)
));
// CVS Westside SF: HEALTHY surplus — eligible source (cold-chain capable)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 200,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(90)
));
// CVS Eastside Oakland: HEALTHY but NOT cold-chain capable — will be filtered out
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Eastside Oakland'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 150,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(60)
));

// =========================================================================
// Scenario 2: Adderall XR 30mg — Schedule II Compliance Block
// =========================================================================
// CVS Downtown SF: LOW stock — will trigger Schedule II hard stop
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Adderall XR 30mg'),
    Quantity__c     = 5,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(180)
));
// CVS San Jose Central: HEALTHY surplus — but will never be reached (Schedule II blocks first)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Adderall XR 30mg'),
    Quantity__c     = 100,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(150)
));

// =========================================================================
// Scenario 3: Lisinopril 10mg — No Suitable Source (Distributor Fallback)
// =========================================================================
// CVS Downtown SF: OUT_OF_STOCK — no other store has surplus
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Lisinopril 10mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 60,
    Expiry_Date__c  = Date.today().addDays(90)
));
// CVS Westside SF: Also LOW — not enough surplus to qualify
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Lisinopril 10mg'),
    Quantity__c     = 30,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(45)
));

// =========================================================================
// Scenario 4: Ozempic 1mg — Near-Expiry Source Exclusion
// =========================================================================
// CVS San Jose Central: LOW stock — target
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 5,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(180)
));
// CVS Downtown SF: HEALTHY surplus but expiring in 15 days — will be EXCLUDED (< 30 day threshold)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 100,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(15)     // Below MIN_DAYS_TO_EXPIRY = 30
));
// CVS Westside SF: HEALTHY surplus with good expiry — should be selected as source
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 80,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(120)
));

// =========================================================================
// Scenario 5: Xanax 0.5mg — Schedule IV (Allowed, Standard Transfer)
// =========================================================================
// CVS Eastside Oakland: LOW stock — target
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Eastside Oakland'),
    Medication__c   = medMap.get('Xanax 0.5mg'),
    Quantity__c     = 10,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(200)
));
// CVS San Jose Central: HEALTHY surplus — eligible source
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Xanax 0.5mg'),
    Quantity__c     = 150,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(180)
));

// =========================================================================
// Scenario 6: Amoxicillin 500mg — Multiple Healthy Stores
// =========================================================================
// CVS Sunnyvale: OUT_OF_STOCK — target
// Note: CVS Sunnyvale has no DEA registration — but it's the TARGET, not the source,
//       so DEA reg check applies to source stores only
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Sunnyvale'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(90)
));
// CVS Downtown SF: HEALTHY — eligible source
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 300,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(150)
));
// CVS San Jose Central: HEALTHY — also eligible, but lower qty so won't be first pick
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 120,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(100)
));

insert positions;

System.debug('========================================');
System.debug('Created ' + positions.size() + ' Inventory Position records:');
System.debug('');
System.debug('DEMO SCENARIOS READY:');
System.debug('  1. Mounjaro 5mg at CVS Downtown SF     → Happy Path (cold-chain transfer from CVS Westside SF)');
System.debug('  2. Adderall XR 30mg at CVS Downtown SF  → Schedule II Compliance Hard Stop');
System.debug('  3. Lisinopril 10mg at CVS Downtown SF   → No Suitable Source (distributor fallback)');
System.debug('  4. Ozempic 1mg at CVS San Jose Central   → Near-Expiry Source Excluded (selects CVS Westside SF)');
System.debug('  5. Xanax 0.5mg at CVS Eastside Oakland   → Schedule IV Allowed Transfer');
System.debug('  6. Amoxicillin 500mg at CVS Sunnyvale    → Multiple Sources (highest qty wins)');
System.debug('========================================');
