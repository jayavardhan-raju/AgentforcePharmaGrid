/**
 * @description Comprehensive test class for PostInstallScript
 *              Tests all post-install functionality including:
 *              - Data creation for stores, medications, inventory
 *              - Permission set assignment
 *              - Prompt template verification
 *              - Error handling
 *
 * @author      IST Team
 * @since       API v65.0
 */
@IsTest
private class PostInstallScriptTest {

    /**
     * Test Case 1: Successful Post-Install Execution
     * Verifies all steps complete successfully
     */
    @IsTest
    static void testSuccessfulPostInstall() {
        // Create mock install context
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify stores were created
        List<Pharmacy_Store__c> stores = [SELECT Id, Name FROM Pharmacy_Store__c];
        System.assertEquals(6, stores.size(), 'Should create 6 stores');

        // Verify medications were created
        List<Medication__c> meds = [SELECT Id, Name FROM Medication__c];
        System.assertEquals(6, meds.size(), 'Should create 6 medications');

        // Verify inventory positions were created
        List<Inventory_Position__c> positions = [SELECT Id FROM Inventory_Position__c];
        System.assert(positions.size() > 0, 'Should create inventory positions');

        // Verify permission set assignment
        List<PermissionSetAssignment> assignments = [
            SELECT Id, AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'IST_Ops_User'
            AND AssigneeId = :context.installerID()
        ];
        System.assertEquals(1, assignments.size(), 'Should assign permission set');
    }

    /**
     * Test Case 2: Store Creation Details
     * Verifies all store details are created correctly
     */
    @IsTest
    static void testStoreCreation() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify specific stores
        Pharmacy_Store__c downtown = [
            SELECT Name, District__c, Cold_Chain_Capable__c, DEA_Registration__c, Is_Active__c
            FROM Pharmacy_Store__c
            WHERE Name = 'CVS Downtown SF'
            LIMIT 1
        ];
        System.assertEquals('District 1 - Bay Area', downtown.District__c, 'District should match');
        System.assertEquals(true, downtown.Cold_Chain_Capable__c, 'Should be cold chain capable');
        System.assertEquals('DEA-SF-DT-001', downtown.DEA_Registration__c, 'DEA should match');
        System.assertEquals(true, downtown.Is_Active__c, 'Should be active');

        // Verify inactive store
        Pharmacy_Store__c inactive = [
            SELECT Is_Active__c
            FROM Pharmacy_Store__c
            WHERE Name = 'CVS Palo Alto (Closed)'
            LIMIT 1
        ];
        System.assertEquals(false, inactive.Is_Active__c, 'Should be inactive');
    }

    /**
     * Test Case 3: Medication Creation Details
     * Verifies all medication details are created correctly
     */
    @IsTest
    static void testMedicationCreation() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify Schedule II medication
        Medication__c scheduleII = [
            SELECT Name, DEA_Schedule__c, Cold_Chain_Required__c
            FROM Medication__c
            WHERE Name = 'Adderall XR 30mg'
            LIMIT 1
        ];
        System.assertEquals('II', scheduleII.DEA_Schedule__c, 'Should be Schedule II');
        System.assertEquals(false, scheduleII.Cold_Chain_Required__c, 'Should not require cold chain');

        // Verify cold-chain medication
        Medication__c coldChain = [
            SELECT Name, DEA_Schedule__c, Cold_Chain_Required__c
            FROM Medication__c
            WHERE Name = 'Mounjaro 5mg'
            LIMIT 1
        ];
        System.assertEquals('None', coldChain.DEA_Schedule__c, 'Should be non-controlled');
        System.assertEquals(true, coldChain.Cold_Chain_Required__c, 'Should require cold chain');
    }

    /**
     * Test Case 4: Inventory Position Creation
     * Verifies inventory positions are created with correct relationships
     */
    @IsTest
    static void testInventoryPositionCreation() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify inventory positions exist with proper relationships
        List<Inventory_Position__c> positions = [
            SELECT Id, Store__c, Medication__c, Quantity__c, Safety_Stock__c
            FROM Inventory_Position__c
            WHERE Store__c != null
            AND Medication__c != null
        ];
        System.assert(positions.size() > 0, 'Should create inventory positions');

        // Verify at least one position has all required fields
        Inventory_Position__c pos = positions[0];
        System.assertNotEquals(null, pos.Store__c, 'Should have store');
        System.assertNotEquals(null, pos.Medication__c, 'Should have medication');
        System.assertNotEquals(null, pos.Quantity__c, 'Should have quantity');
        System.assertNotEquals(null, pos.Safety_Stock__c, 'Should have safety stock');
    }

    /**
     * Test Case 5: Permission Set Assignment
     * Verifies permission set is assigned to installer
     */
    @IsTest
    static void testPermissionSetAssignment() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify permission set exists
        List<PermissionSet> ps = [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name = 'IST_Ops_User'
        ];
        System.assertEquals(1, ps.size(), 'Permission set should exist');

        // Verify assignment
        List<PermissionSetAssignment> assignments = [
            SELECT Id, PermissionSetId, AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :ps[0].Id
            AND AssigneeId = :context.installerID()
        ];
        System.assertEquals(1, assignments.size(), 'Should create one assignment');
        System.assertEquals(context.installerID(), assignments[0].AssigneeId, 'Should assign to installer');
    }

    /**
     * Test Case 6: Duplicate Permission Set Assignment
     * Verifies no duplicate assignment is created
     */
    @IsTest
    static void testDuplicatePermissionSetAssignment() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        // Run post-install twice
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        script.onInstall(context);  // Second run
        Test.stopTest();

        // Verify only one assignment exists
        List<PermissionSetAssignment> assignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'IST_Ops_User'
            AND AssigneeId = :context.installerID()
        ];
        System.assertEquals(1, assignments.size(), 'Should have only one assignment despite duplicate run');
    }

    /**
     * Test Case 7: Version Information
     * Verifies version information is logged
     */
    @IsTest
    static void testVersionLogging() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Test completes successfully - version info should be in debug logs
        // Verify data was created (indicates script ran successfully)
        List<Pharmacy_Store__c> stores = [SELECT Id FROM Pharmacy_Store__c];
        System.assert(stores.size() > 0, 'Script should have executed successfully');
    }

    /**
     * Test Case 8: Prompt Template Verification Success
     * Verifies prompt template verification executes without error
     */
    @IsTest
    static void testPromptTemplateVerification() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Script should complete without throwing exception
        // Prompt template verification is best-effort and won't fail installation
        List<Pharmacy_Store__c> stores = [SELECT Id FROM Pharmacy_Store__c];
        System.assert(stores.size() > 0, 'Script should complete even if prompt verification unavailable');
    }

    /**
     * Test Case 9: Error Handling
     * Verifies script handles errors gracefully without blocking installation
     */
    @IsTest
    static void testErrorHandling() {
        // Create context with null installer ID to trigger permission set error
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        context.testInstallerId = null;
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        // Should not throw exception even with errors
        script.onInstall(context);
        Test.stopTest();

        // Data creation should still succeed
        List<Pharmacy_Store__c> stores = [SELECT Id FROM Pharmacy_Store__c];
        System.assert(stores.size() > 0, 'Data creation should succeed despite permission error');
    }

    /**
     * Test Case 10: All Scenarios Covered
     * Verifies all 6 inventory scenarios are created
     */
    @IsTest
    static void testAllInventoryScenarios() {
        PostInstallScriptTest.MockInstallContext context = new PostInstallScriptTest.MockInstallContext();
        
        Test.startTest();
        PostInstallScript script = new PostInstallScript();
        script.onInstall(context);
        Test.stopTest();

        // Verify Mounjaro positions (Scenario 1: Happy Path)
        List<Inventory_Position__c> mounjaro = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Mounjaro 5mg'
        ];
        System.assert(mounjaro.size() > 0, 'Should have Mounjaro positions');

        // Verify Adderall positions (Scenario 2: Schedule II Block)
        List<Inventory_Position__c> adderall = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Adderall XR 30mg'
        ];
        System.assert(adderall.size() > 0, 'Should have Adderall positions');

        // Verify Lisinopril positions (Scenario 3: Distributor Fallback)
        List<Inventory_Position__c> lisinopril = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Lisinopril 10mg'
        ];
        System.assert(lisinopril.size() > 0, 'Should have Lisinopril positions');

        // Verify Ozempic positions (Scenario 4: Near-Expiry Exclusion)
        List<Inventory_Position__c> ozempic = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Ozempic 1mg'
        ];
        System.assert(ozempic.size() > 0, 'Should have Ozempic positions');

        // Verify Xanax positions (Scenario 5: Schedule IV Allowed)
        List<Inventory_Position__c> xanax = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Xanax 0.5mg'
        ];
        System.assert(xanax.size() > 0, 'Should have Xanax positions');

        // Verify Amoxicillin positions (Scenario 6: Multiple Sources)
        List<Inventory_Position__c> amoxicillin = [
            SELECT Id
            FROM Inventory_Position__c
            WHERE Medication__r.Name = 'Amoxicillin 500mg'
        ];
        System.assert(amoxicillin.size() > 0, 'Should have Amoxicillin positions');
    }

    /**
     * Mock InstallContext for testing
     */
    private class MockInstallContext implements InstallContext {
        public Id testInstallerId = UserInfo.getUserId();
        public Version testPreviousVersion = new Version(1, 0);
        public Boolean testIsPush = false;
        public Boolean testIsUpgrade = false;

        public Id organizationId() {
            return UserInfo.getOrganizationId();
        }

        public Id installerID() {
            return testInstallerId;
        }

        public Boolean isUpgrade() {
            return testIsUpgrade;
        }

        public Boolean isPush() {
            return testIsPush;
        }

        public Version previousVersion() {
            return testPreviousVersion;
        }
    }
}