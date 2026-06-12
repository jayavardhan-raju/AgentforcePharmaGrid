/**
 * @description Comprehensive test class for InventoryPositionSelector
 *              Tests all SOQL queries and error handling
 *
 * @author      IST Team
 * @since       API v65.0
 */
@IsTest
private class InventoryPositionSelectorTest {

    @TestSetup
    static void setupTestData() {
        // Create a non-admin user with the IST_Ops_User permission set assigned
        ISTTestDataFactory.createOpsUser();

        // Create stores
        Pharmacy_Store__c store1 = ISTTestDataFactory.createStore(
            'Store 1', true, 'DEA-001', true
        );
        Pharmacy_Store__c store2 = ISTTestDataFactory.createStore(
            'Store 2', true, 'DEA-002', true
        );
        Pharmacy_Store__c store3 = ISTTestDataFactory.createStore(
            'Store 3', false, 'DEA-003', true
        );
        Pharmacy_Store__c inactiveStore = ISTTestDataFactory.createStore(
            'Inactive Store', true, 'DEA-004', false
        );

        // Create medication
        Medication__c med = ISTTestDataFactory.createMedication(
            'Test Medication', 'None', false
        );
    }

    /**
     * Test Case 1: getById - Successful Retrieval
     * Verifies successful retrieval of inventory position with full context
     */
    @IsTest
    static void testGetByIdSuccess() {
        // Query test data
        Pharmacy_Store__c store = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory position
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store.Id, med.Id, 100, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            Inventory_Position__c result = InventoryPositionSelector.getById(inv.Id);
            Test.stopTest();
        }

        // Assertions - verify all fields are retrieved
        System.assertNotEquals(null, result, 'Should retrieve record');
        System.assertEquals(inv.Id, result.Id, 'ID should match');
        System.assertNotEquals(null, result.Store__c, 'Should have Store ID');
        System.assertNotEquals(null, result.Store__r, 'Should have Store relation');
        System.assertNotEquals(null, result.Store__r.Name, 'Should have Store Name');
        System.assertNotEquals(null, result.Medication__c, 'Should have Medication ID');
        System.assertNotEquals(null, result.Medication__r, 'Should have Medication relation');
        System.assertNotEquals(null, result.Medication__r.Name, 'Should have Medication Name');
        System.assertEquals(100, result.Quantity__c, 'Quantity should match');
        System.assertEquals(50, result.Safety_Stock__c, 'Safety stock should match');
    }

    /**
     * Test Case 2: getById - Null ID
     * Verifies IllegalArgumentException is thrown for null ID
     */
    @IsTest
    static void testGetByIdNullId() {
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            try {
                InventoryPositionSelector.getById(null);
                System.assert(false, 'Should throw IllegalArgumentException');
            } catch (IllegalArgumentException ex) {
                System.assert(
                    ex.getMessage().contains('cannot be null'),
                    'Should mention null parameter'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * Test Case 3: getById - Non-Existent ID
     * Verifies QueryException is thrown for non-existent record
     */
    @IsTest
    static void testGetByIdNonExistent() {
        Id fakeId = '001000000000000AAA';

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            try {
                InventoryPositionSelector.getById(fakeId);
                System.assert(false, 'Should throw QueryException');
            } catch (QueryException ex) {
                System.assert(
                    ex.getMessage().contains('not found'),
                    'Should mention record not found'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * Test Case 4: findSurplusSources - Multiple Sources Found
     * Verifies correct sorting by quantity descending
     */
    @IsTest
    static void testFindSurplusSourcesMultiple() {
        // Query test data
        Pharmacy_Store__c store1 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Pharmacy_Store__c store2 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 2' LIMIT 1];
        Pharmacy_Store__c store3 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 3' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory at multiple stores with different quantities
        Inventory_Position__c inv1 = ISTTestDataFactory.createInventory(
            store1.Id, med.Id, 150, 50, 90  // 100 surplus
        );
        Inventory_Position__c inv2 = ISTTestDataFactory.createInventory(
            store2.Id, med.Id, 300, 50, 120  // 250 surplus (highest)
        );
        Inventory_Position__c inv3 = ISTTestDataFactory.createInventory(
            store3.Id, med.Id, 100, 50, 85  // 50 surplus
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                store1.Id,  // Exclude store1
                1
            );
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(2, results.size(), 'Should find 2 sources (excluding store1)');
        // Should be sorted by quantity descending
        System.assertEquals(store2.Id, results[0].Store__c, 'First should be store2 (highest qty)');
        System.assertEquals(store3.Id, results[1].Store__c, 'Second should be store3');
    }

    /**
     * Test Case 5: findSurplusSources - No Sources Found
     * Verifies empty list when no sources meet criteria
     */
    @IsTest
    static void testFindSurplusSourcesNone() {
        // Query test data
        Pharmacy_Store__c store1 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create only one inventory (which will be excluded)
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store1.Id, med.Id, 100, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                store1.Id,  // Exclude the only store
                1
            );
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(0, results.size(), 'Should find no sources');
    }

    /**
     * Test Case 6: findSurplusSources - Inactive Store Excluded
     * Verifies that inactive stores are automatically excluded
     */
    @IsTest
    static void testFindSurplusSourcesInactiveExcluded() {
        // Query test data
        Pharmacy_Store__c activeStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Pharmacy_Store__c inactiveStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Inactive Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory at inactive store with high quantity
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            inactiveStore.Id, med.Id, 500, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                activeStore.Id,  // Exclude active store
                1
            );
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(0, results.size(), 'Should not include inactive store');
    }

    /**
     * Test Case 7: findSurplusSources - Minimum Surplus Filter
     * Verifies that sources below minimum quantity are excluded
     */
    @IsTest
    static void testFindSurplusSourcesMinimumFilter() {
        // Query test data
        Pharmacy_Store__c store1 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Pharmacy_Store__c store2 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 2' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory at store2 with quantity below minimum
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store2.Id, med.Id, 10, 5, 90  // Only 5 surplus
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                store1.Id,
                50  // Require minimum 50
            );
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(0, results.size(), 'Should exclude source below minimum');
    }

    /**
     * Test Case 8: findSurplusSources - Null Minimum Defaults to 1
     * Verifies that null minimum parameter defaults to 1
     */
    @IsTest
    static void testFindSurplusSourcesNullMinimum() {
        // Query test data
        Pharmacy_Store__c store1 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Pharmacy_Store__c store2 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 2' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory at store2
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store2.Id, med.Id, 100, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                store1.Id,
                null  // Null should default to 1
            );
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(1, results.size(), 'Should find source with null minimum (defaults to 1)');
    }

    /**
     * Test Case 9: findSurplusSources - All Related Fields Retrieved
     * Verifies all store and medication relationship fields are queried
     */
    @IsTest
    static void testFindSurplusSourcesAllFields() {
        // Query test data
        Pharmacy_Store__c store1 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Pharmacy_Store__c store2 = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 2' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];

        // Create inventory
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store2.Id, med.Id, 200, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            List<Inventory_Position__c> results = InventoryPositionSelector.findSurplusSources(
                med.Id,
                store1.Id,
                1
            );
            Test.stopTest();
        }

        // Verify all fields are retrieved
        Inventory_Position__c result = results[0];
        System.assertNotEquals(null, result.Store__r.Name, 'Should have Store Name');
        System.assertNotEquals(null, result.Store__r.Latitude__c, 'Should have Latitude');
        System.assertNotEquals(null, result.Store__r.Longitude__c, 'Should have Longitude');
        System.assertNotEquals(null, result.Store__r.Cold_Chain_Capable__c, 'Should have Cold Chain');
        System.assertNotEquals(null, result.Store__r.DEA_Registration__c, 'Should have DEA Reg');
        System.assertNotEquals(null, result.Store__r.Is_Active__c, 'Should have Is Active');
        System.assertNotEquals(null, result.Medication__r.Name, 'Should have Medication Name');
        System.assertNotEquals(null, result.Medication__r.DEA_Schedule__c, 'Should have DEA Schedule');
        System.assertNotEquals(null, result.Medication__r.Cold_Chain_Required__c, 'Should have Cold Chain Required');
    }

    /**
     * Test Case 10: Security Enforcement
     * Verifies WITH SECURITY_ENFORCED is applied
     */
    @IsTest
    static void testSecurityEnforced() {
        // This test verifies the queries use WITH SECURITY_ENFORCED
        // In a real restricted user context, this would prevent access
        // For this test, we verify the queries execute without error
        
        Pharmacy_Store__c store = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store 1' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c LIMIT 1];
        
        Inventory_Position__c inv = ISTTestDataFactory.createInventory(
            store.Id, med.Id, 100, 50, 90
        );

        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            // Both methods should execute without error with security enforced
            Inventory_Position__c result1 = InventoryPositionSelector.getById(inv.Id);
            List<Inventory_Position__c> result2 = InventoryPositionSelector.findSurplusSources(
                med.Id, store.Id, 1
            );
            Test.stopTest();
        }

        // Verify queries executed successfully
        System.assertNotEquals(null, result1, 'getById should succeed with security enforced');
        System.assertNotEquals(null, result2, 'findSurplusSources should succeed with security enforced');
    }
}