/**
 * ============================================================================
 * Post-Install Script for AgentforcePharmaGrid Package
 * ============================================================================
 * 
 * Executes automatically after package installation to:
 *   1. Create sample Pharmacy Store records
 *   2. Create sample Medication records
 *   3. Create Inventory Position records with various scenarios
 *   4. Assign IST_Ops_User permission set to deployment user
 *   5. Check whether IST Inventory Recommendation prompt template exists
 *
 * This script implements the InstallHandler interface and is referenced in
 * the package.xml postInstallClass attribute.
 *
 * NOTE: The IST_Inventory_Recommendation prompt template is NOT deployed by
 * this package. Salesforce's GenAiPromptTemplate metadata requires server-
 * generated hash identifiers that cannot be authored by hand, so admins must
 * create it manually in Prompt Builder per
 * docs/setup/create-prompt-template.md. Step 5 below only logs whether the
 * template is present; it does not create or deploy it.
 * ============================================================================
 */
public class PostInstallScript implements InstallHandler {
    
    /**
     * Main entry point called by Salesforce after package installation
     */
    public void onInstall(InstallContext context) {
        try {
            System.debug('========================================');
            System.debug('Starting Post-Install Script');
            System.debug('Version: ' + context.previousVersion());
            System.debug('Installation User: ' + UserInfo.getUserId());
            System.debug('========================================');
            
            // Step 1: Create Pharmacy Stores
            createPharmacyStores();
            
            // Step 2: Create Medications
            createMedications();
            
            // Step 3: Create Inventory Positions
            createInventoryPositions();
            
            // Step 4: Assign Permission Set
            assignPermissionSet(context.installerID());
            
            // Step 5: Check whether the prompt template has been created manually
            verifyPromptTemplate();
            
            System.debug('========================================');
            System.debug('Post-Install Script Completed Successfully');
            System.debug('========================================');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Post-Install Script Failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            // Note: We don't throw the exception to avoid blocking the installation
            // The admin can review debug logs and manually run data scripts if needed
        }
    }
    
    /**
     * Step 1: Create Pharmacy Store Records
     * Creates 6 pharmacy stores across 2 districts with varied capabilities
     */
    private void createPharmacyStores() {
        System.debug('Step 1: Creating Pharmacy Stores...');
        
        List<Pharmacy_Store__c> stores = new List<Pharmacy_Store__c>{
            // District 1: San Francisco Bay Area
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
                Cold_Chain_Capable__c = false,
                DEA_Registration__c   = 'DEA-OAK-ES-003',
                Is_Active__c          = true
            ),
            // District 2: South Bay
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
                DEA_Registration__c   = '',
                Is_Active__c          = true
            ),
            new Pharmacy_Store__c(
                Name                  = 'CVS Palo Alto (Closed)',
                District__c           = 'District 2 - South Bay',
                Latitude__c           = 37.4419,
                Longitude__c          = -122.1430,
                Cold_Chain_Capable__c = true,
                DEA_Registration__c   = 'DEA-PA-CL-006',
                Is_Active__c          = false
            )
        };
        
        insert stores;
        System.debug('Created ' + stores.size() + ' Pharmacy Store records');
    }
    
    /**
     * Step 2: Create Medication Records
     * Creates 6 medications with varied regulatory and handling attributes
     */
    private void createMedications() {
        System.debug('Step 2: Creating Medications...');
        
        List<Medication__c> meds = new List<Medication__c>{
            // Cold-Chain + Non-Controlled
            new Medication__c(
                Name                    = 'Mounjaro 5mg',
                NDC__c                  = '00002-1523-80',
                DEA_Schedule__c         = 'None',
                Cold_Chain_Required__c  = true
            ),
            new Medication__c(
                Name                    = 'Ozempic 1mg',
                NDC__c                  = '00169-4132-12',
                DEA_Schedule__c         = 'None',
                Cold_Chain_Required__c  = true
            ),
            // Schedule II Controlled Substance (Hard Compliance Block)
            new Medication__c(
                Name                    = 'Adderall XR 30mg',
                NDC__c                  = '54092-0391-01',
                DEA_Schedule__c         = 'II',
                Cold_Chain_Required__c  = false
            ),
            // Schedule IV Controlled (Allowed for automated transfer)
            new Medication__c(
                Name                    = 'Xanax 0.5mg',
                NDC__c                  = '00009-0055-01',
                DEA_Schedule__c         = 'IV',
                Cold_Chain_Required__c  = false
            ),
            // Standard Non-Controlled
            new Medication__c(
                Name                    = 'Lisinopril 10mg',
                NDC__c                  = '00093-1044-01',
                DEA_Schedule__c         = 'None',
                Cold_Chain_Required__c  = false
            ),
            new Medication__c(
                Name                    = 'Amoxicillin 500mg',
                NDC__c                  = '65862-0015-01',
                DEA_Schedule__c         = 'None',
                Cold_Chain_Required__c  = false
            )
        };
        
        insert meds;
        System.debug('Created ' + meds.size() + ' Medication records');
    }
    
    /**
     * Step 3: Create Inventory Position Records
     * Creates inventory positions that demonstrate various transfer scenarios
     */
    private void createInventoryPositions() {
        System.debug('Step 3: Creating Inventory Positions...');
        
        // Query prerequisite data
        Set<String> expectedStores = new Set<String>{
            'CVS Downtown SF', 'CVS Westside SF', 'CVS Eastside Oakland',
            'CVS San Jose Central', 'CVS Sunnyvale'
        };
        Set<String> expectedMeds = new Set<String>{
            'Mounjaro 5mg', 'Ozempic 1mg', 'Adderall XR 30mg',
            'Xanax 0.5mg', 'Lisinopril 10mg', 'Amoxicillin 500mg'
        };
        
        Map<String, Id> storeMap = new Map<String, Id>();
        for (Pharmacy_Store__c s : [
            SELECT Id, Name FROM Pharmacy_Store__c WHERE Name IN :expectedStores
        ]) {
            storeMap.put(s.Name, s.Id);
        }
        
        Map<String, Id> medMap = new Map<String, Id>();
        for (Medication__c m : [
            SELECT Id, Name FROM Medication__c WHERE Name IN :expectedMeds
        ]) {
            medMap.put(m.Name, m.Id);
        }
        
        List<Inventory_Position__c> positions = new List<Inventory_Position__c>();
        
        // Scenario 1: Mounjaro 5mg — Happy Path Transfer (Cold-Chain Required)
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Downtown SF'),
            Medication__c = medMap.get('Mounjaro 5mg'),
            Quantity__c = 0,
            Safety_Stock__c = 50,
            Expiry_Date__c = Date.today().addDays(120)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Westside SF'),
            Medication__c = medMap.get('Mounjaro 5mg'),
            Quantity__c = 200,
            Safety_Stock__c = 50,
            Expiry_Date__c = Date.today().addDays(90)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Eastside Oakland'),
            Medication__c = medMap.get('Mounjaro 5mg'),
            Quantity__c = 150,
            Safety_Stock__c = 40,
            Expiry_Date__c = Date.today().addDays(60)
        ));
        
        // Scenario 2: Adderall XR 30mg — Schedule II Compliance Block
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Downtown SF'),
            Medication__c = medMap.get('Adderall XR 30mg'),
            Quantity__c = 5,
            Safety_Stock__c = 30,
            Expiry_Date__c = Date.today().addDays(180)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS San Jose Central'),
            Medication__c = medMap.get('Adderall XR 30mg'),
            Quantity__c = 100,
            Safety_Stock__c = 20,
            Expiry_Date__c = Date.today().addDays(150)
        ));
        
        // Scenario 3: Lisinopril 10mg — No Suitable Source (Distributor Fallback)
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Downtown SF'),
            Medication__c = medMap.get('Lisinopril 10mg'),
            Quantity__c = 0,
            Safety_Stock__c = 60,
            Expiry_Date__c = Date.today().addDays(90)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Westside SF'),
            Medication__c = medMap.get('Lisinopril 10mg'),
            Quantity__c = 30,
            Safety_Stock__c = 50,
            Expiry_Date__c = Date.today().addDays(45)
        ));
        
        // Scenario 4: Ozempic 1mg — Near-Expiry Source Exclusion
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS San Jose Central'),
            Medication__c = medMap.get('Ozempic 1mg'),
            Quantity__c = 5,
            Safety_Stock__c = 40,
            Expiry_Date__c = Date.today().addDays(180)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Downtown SF'),
            Medication__c = medMap.get('Ozempic 1mg'),
            Quantity__c = 100,
            Safety_Stock__c = 20,
            Expiry_Date__c = Date.today().addDays(15)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Westside SF'),
            Medication__c = medMap.get('Ozempic 1mg'),
            Quantity__c = 80,
            Safety_Stock__c = 20,
            Expiry_Date__c = Date.today().addDays(120)
        ));
        
        // Scenario 5: Xanax 0.5mg — Schedule IV (Allowed, Standard Transfer)
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Eastside Oakland'),
            Medication__c = medMap.get('Xanax 0.5mg'),
            Quantity__c = 10,
            Safety_Stock__c = 40,
            Expiry_Date__c = Date.today().addDays(200)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS San Jose Central'),
            Medication__c = medMap.get('Xanax 0.5mg'),
            Quantity__c = 150,
            Safety_Stock__c = 30,
            Expiry_Date__c = Date.today().addDays(180)
        ));
        
        // Scenario 6: Amoxicillin 500mg — Multiple Healthy Stores
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Sunnyvale'),
            Medication__c = medMap.get('Amoxicillin 500mg'),
            Quantity__c = 0,
            Safety_Stock__c = 50,
            Expiry_Date__c = Date.today().addDays(90)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS Downtown SF'),
            Medication__c = medMap.get('Amoxicillin 500mg'),
            Quantity__c = 300,
            Safety_Stock__c = 40,
            Expiry_Date__c = Date.today().addDays(150)
        ));
        positions.add(new Inventory_Position__c(
            Store__c = storeMap.get('CVS San Jose Central'),
            Medication__c = medMap.get('Amoxicillin 500mg'),
            Quantity__c = 120,
            Safety_Stock__c = 30,
            Expiry_Date__c = Date.today().addDays(100)
        ));
        
        insert positions;
        System.debug('Created ' + positions.size() + ' Inventory Position records');
    }
    
    /**
     * Step 4: Assign Permission Set to Installation User
     * Assigns IST_Ops_User permission set to the user who installed the package
     */
    private void assignPermissionSet(Id userId) {
        System.debug('Step 4: Assigning Permission Set...');
        
        try {
            // Query the permission set
            PermissionSet ps = [
                SELECT Id, Name 
                FROM PermissionSet 
                WHERE Name = 'IST_Ops_User' 
                LIMIT 1
            ];
            
            // Check if assignment already exists
            List<PermissionSetAssignment> existingAssignments = [
                SELECT Id 
                FROM PermissionSetAssignment 
                WHERE PermissionSetId = :ps.Id 
                AND AssigneeId = :userId
            ];
            
            if (existingAssignments.isEmpty()) {
                // Create new assignment
                PermissionSetAssignment psa = new PermissionSetAssignment(
                    PermissionSetId = ps.Id,
                    AssigneeId = userId
                );
                insert psa;
                System.debug('Permission Set IST_Ops_User assigned to user: ' + userId);
            } else {
                System.debug('Permission Set IST_Ops_User already assigned to user: ' + userId);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to assign permission set: ' + e.getMessage());
            // Don't throw - log the error but continue with installation
        }
    }
    
    /**
     * Step 5: Check whether the IST_Inventory_Recommendation prompt template
     * has already been created in Prompt Builder. This template is not
     * deployed by the package; admins create it manually per
     * docs/setup/create-prompt-template.md.
     */
    private void verifyPromptTemplate() {
        System.debug('Step 5: Checking Prompt Template...');

        try {
            List<SObject> prompts = Database.query(
                'SELECT Id, DeveloperName, MasterLabel, ActiveVersion FROM AiPrompt ' +
                'WHERE DeveloperName = \'IST_Inventory_Recommendation\' LIMIT 1'
            );

            if (!prompts.isEmpty()) {
                SObject prompt = prompts[0];
                System.debug('Prompt Template found:');
                System.debug('  - Name: ' + prompt.get('MasterLabel'));
                System.debug('  - API Name: ' + prompt.get('DeveloperName'));
                System.debug('  - Active Version: ' + prompt.get('ActiveVersion'));
                System.debug('  - ID: ' + prompt.get('Id'));
            } else {
                System.debug(LoggingLevel.WARN,
                    'Prompt Template IST_Inventory_Recommendation not found. ' +
                    'Create it manually in Prompt Builder per ' +
                    'docs/setup/create-prompt-template.md before using the grid.');
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.INFO,
                'Could not query AiPrompt: ' + e.getMessage());
            System.debug(LoggingLevel.INFO,
                'This is expected if Agentforce is not enabled in this org.');
        }
    }
}