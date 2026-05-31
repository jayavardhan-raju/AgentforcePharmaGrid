/**
 * ============================================================================
 * Script 1 of 3: Create Pharmacy Store Records
 * ============================================================================
 * 
 * Run via: sf apex run --file scripts/data/1_Create_Pharmacy_Stores.apex --target-org <alias>
 * 
 * Creates 6 pharmacy stores across 2 districts with varied capabilities:
 *   - Cold-chain capable vs. not capable
 *   - With/without DEA registration
 *   - Active vs. inactive
 * 
 * This variety is required to exercise all source selection filter paths
 * in InterStoreTransferService.selectBestSource().
 * ============================================================================
 */

List<Pharmacy_Store__c> stores = new List<Pharmacy_Store__c>{

    // ── District 1: San Francisco Bay Area ────────────────────────────────
    new Pharmacy_Store__c(
        Name                  = 'CVS Downtown SF',
        District__c           = 'District 1 - Bay Area',
        Latitude__c           = 37.7749,
        Longitude__c          = -122.4194,
        Cold_Chain_Capable__c = true,
        DEA_Registration__c   = 'DEA-SF-DT-001',
        Is_Active__c          = true
    ),
    new Pharmacy_Store__c(
        Name                  = 'CVS Westside SF',
        District__c           = 'District 1 - Bay Area',
        Latitude__c           = 37.7599,
        Longitude__c          = -122.5107,
        Cold_Chain_Capable__c = true,
        DEA_Registration__c   = 'DEA-SF-WS-002',
        Is_Active__c          = true
    ),
    new Pharmacy_Store__c(
        Name                  = 'CVS Eastside Oakland',
        District__c           = 'District 1 - Bay Area',
        Latitude__c           = 37.8044,
        Longitude__c          = -122.2712,
        Cold_Chain_Capable__c = false,          // No cold chain — will be filtered out for cold-chain meds
        DEA_Registration__c   = 'DEA-OAK-ES-003',
        Is_Active__c          = true
    ),

    // ── District 2: South Bay ─────────────────────────────────────────────
    new Pharmacy_Store__c(
        Name                  = 'CVS San Jose Central',
        District__c           = 'District 2 - South Bay',
        Latitude__c           = 37.3382,
        Longitude__c          = -121.8863,
        Cold_Chain_Capable__c = true,
        DEA_Registration__c   = 'DEA-SJ-CT-004',
        Is_Active__c          = true
    ),
    new Pharmacy_Store__c(
        Name                  = 'CVS Sunnyvale',
        District__c           = 'District 2 - South Bay',
        Latitude__c           = 37.3688,
        Longitude__c          = -122.0363,
        Cold_Chain_Capable__c = true,
        DEA_Registration__c   = '',             // No DEA registration — will be filtered out
        Is_Active__c          = true
    ),
    new Pharmacy_Store__c(
        Name                  = 'CVS Palo Alto (Closed)',
        District__c           = 'District 2 - South Bay',
        Latitude__c           = 37.4419,
        Longitude__c          = -122.1430,
        Cold_Chain_Capable__c = true,
        DEA_Registration__c   = 'DEA-PA-CL-006',
        Is_Active__c          = false           // Inactive — excluded by SOQL WHERE clause
    )
};

insert stores;

System.debug('========================================');
System.debug('Created ' + stores.size() + ' Pharmacy Store records:');
for (Pharmacy_Store__c s : stores) {
    System.debug('  [' + s.Id + '] ' + s.Name
        + ' | Cold Chain: ' + s.Cold_Chain_Capable__c
        + ' | DEA: ' + (String.isNotBlank(s.DEA_Registration__c) ? s.DEA_Registration__c : 'NONE')
        + ' | Active: ' + s.Is_Active__c);
}
System.debug('========================================');
