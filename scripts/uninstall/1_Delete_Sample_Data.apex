/**
 * ============================================================================
 * Uninstall Script 1 of 2: Delete Sample Data
 * ============================================================================
 * 
 * Run via: sf apex run --file scripts/uninstall/1_Delete_Sample_Data.apex --target-org <alias>
 * 
 * Deletes all sample data created by the PostInstallScript:
 *   - Inventory Position records
 *   - Medication records
 *   - Pharmacy Store records
 *   - Transfer Log records (if any)
 * 
 * IMPORTANT: Run this BEFORE deploying destructiveChanges.xml
 *            Data must be deleted before objects can be removed
 * ============================================================================
 */

System.debug('========================================');
System.debug('Starting Sample Data Deletion');
System.debug('========================================');

// Step 1: Delete Transfer Log records (if any exist)
List<Transfer_Log__c> transferLogs = [SELECT Id FROM Transfer_Log__c];
if (!transferLogs.isEmpty()) {
    delete transferLogs;
    System.debug('Deleted ' + transferLogs.size() + ' Transfer Log records');
} else {
    System.debug('No Transfer Log records found');
}

// Step 2: Delete Inventory Position records
List<Inventory_Position__c> positions = [SELECT Id FROM Inventory_Position__c];
if (!positions.isEmpty()) {
    delete positions;
    System.debug('Deleted ' + positions.size() + ' Inventory Position records');
} else {
    System.debug('No Inventory Position records found');
}

// Step 3: Delete Medication records
List<Medication__c> medications = [SELECT Id FROM Medication__c];
if (!medications.isEmpty()) {
    delete medications;
    System.debug('Deleted ' + medications.size() + ' Medication records');
} else {
    System.debug('No Medication records found');
}

// Step 4: Delete Pharmacy Store records
List<Pharmacy_Store__c> stores = [SELECT Id FROM Pharmacy_Store__c];
if (!stores.isEmpty()) {
    delete stores;
    System.debug('Deleted ' + stores.size() + ' Pharmacy Store records');
} else {
    System.debug('No Pharmacy Store records found');
}

System.debug('========================================');
System.debug('Sample Data Deletion Complete');
System.debug('========================================');
System.debug('Next Step: Run script 2_Remove_Permission_Sets.apex');