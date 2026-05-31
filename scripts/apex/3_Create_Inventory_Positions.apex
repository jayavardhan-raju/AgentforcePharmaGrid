

Set<String> expectedStores = new Set<String>{
    'CVS Downtown SF',
    'CVS Westside SF',
    'CVS Eastside Oakland',
    'CVS San Jose Central',
    'CVS Sunnyvale'
};
Set<String> expectedMeds = new Set<String>{
    'Mounjaro 5mg',
    'Ozempic 1mg',
    'Adderall XR 30mg',
    'Xanax 0.5mg',
    'Lisinopril 10mg',
    'Amoxicillin 500mg'
};

// ── Query Stores (created by Script 1) ───────────────────────────────────
Map<String, Id> storeMap = new Map<String, Id>();
for (Pharmacy_Store__c s : [
    SELECT Id, Name FROM Pharmacy_Store__c WHERE Name IN :expectedStores
]) {
    storeMap.put(s.Name, s.Id);
}

// ── Query Medications (created by Script 2) ──────────────────────────────
Map<String, Id> medMap = new Map<String, Id>();
for (Medication__c m : [
    SELECT Id, Name FROM Medication__c WHERE Name IN :expectedMeds
]) {
    medMap.put(m.Name, m.Id);
}

// ── Validate every required record exists individually ───────────────────
List<String> missingStores = new List<String>();
for (String n : expectedStores) {
    if (!storeMap.containsKey(n)) missingStores.add(n);
}
List<String> missingMeds = new List<String>();
for (String n : expectedMeds) {
    if (!medMap.containsKey(n)) missingMeds.add(n);
}

if (!missingStores.isEmpty() || !missingMeds.isEmpty()) {
    String msg = 'Prerequisite data missing. ';
    if (!missingStores.isEmpty()) msg += 'Run Script 1. Missing stores: ' + missingStores + '. ';
    if (!missingMeds.isEmpty())   msg += 'Run Script 2. Missing medications: ' + missingMeds + '.';
    throw new System.IllegalArgumentException(msg);
}

System.debug('Found all ' + storeMap.size() + ' stores and ' + medMap.size() + ' medications.');

List<Inventory_Position__c> positions = new List<Inventory_Position__c>();

// Scenario 1: Mounjaro 5mg — Happy Path Transfer (Cold-Chain Required)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(120)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 200,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(90)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Eastside Oakland'),
    Medication__c   = medMap.get('Mounjaro 5mg'),
    Quantity__c     = 150,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(60)
));
// Scenario 2: Adderall XR 30mg — Schedule II Compliance Block
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Adderall XR 30mg'),
    Quantity__c     = 5,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(180)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Adderall XR 30mg'),
    Quantity__c     = 100,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(150)
));

// Scenario 3: Lisinopril 10mg — No Suitable Source (Distributor Fallback)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Lisinopril 10mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 60,
    Expiry_Date__c  = Date.today().addDays(90)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Lisinopril 10mg'),
    Quantity__c     = 30,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(45)
));

// Scenario 4: Ozempic 1mg — Near-Expiry Source Exclusion
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 5,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(180)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 100,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(15)     // Below MIN_DAYS_TO_EXPIRY = 30
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Westside SF'),
    Medication__c   = medMap.get('Ozempic 1mg'),
    Quantity__c     = 80,
    Safety_Stock__c = 20,
    Expiry_Date__c  = Date.today().addDays(120)
));

// Scenario 5: Xanax 0.5mg — Schedule IV (Allowed, Standard Transfer)
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Eastside Oakland'),
    Medication__c   = medMap.get('Xanax 0.5mg'),
    Quantity__c     = 10,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(200)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Xanax 0.5mg'),
    Quantity__c     = 150,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(180)
));

// Scenario 6: Amoxicillin 500mg — Multiple Healthy Stores
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Sunnyvale'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 0,
    Safety_Stock__c = 50,
    Expiry_Date__c  = Date.today().addDays(90)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS Downtown SF'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 300,
    Safety_Stock__c = 40,
    Expiry_Date__c  = Date.today().addDays(150)
));
positions.add(new Inventory_Position__c(
    Store__c        = storeMap.get('CVS San Jose Central'),
    Medication__c   = medMap.get('Amoxicillin 500mg'),
    Quantity__c     = 120,
    Safety_Stock__c = 30,
    Expiry_Date__c  = Date.today().addDays(100)
));

insert positions;

System.debug('Created ' + positions.size() + ' Inventory Position records.');
