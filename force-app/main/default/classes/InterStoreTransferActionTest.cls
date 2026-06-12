/**
 * @description Comprehensive test class for InterStoreTransferAction
 *              Tests the Invocable Action wrapper that calls the service
 *
 * @author      IST Team
 * @since       API v65.0
 */
@IsTest
private class InterStoreTransferActionTest {

    @TestSetup
    static void setupTestData() {
        // Create a non-admin user with the IST_Ops_User permission set assigned
        ISTTestDataFactory.createOpsUser();

        // Create stores
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'Target Store', true, 'DEA-001', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'Source Store', true, 'DEA-002', true
        );

        // Create medications
        Medication__c standardMed = ISTTestDataFactory.createMedication(
            'Standard Medication', 'None', false
        );
        Medication__c scheduleIIMed = ISTTestDataFactory.createMedication(
            'Schedule II Med', 'II', false
        );
    }

    /**
     * Test Case 1: Dry-Run (confirm=false)
     * Verifies the action returns recommendation without execution
     */
    @IsTest
    static void testDryRunAction() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Source Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Standard Medication' LIMIT 1];

        // Create inventory
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        // Prepare action input
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(1, outputs.size(), 'Should return one output');
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Should succeed');
        System.assertNotEquals(null, output.uhText, 'Should have uhText');
        System.assertNotEquals(null, output.sourceStoreId, 'Should have source store');
        System.assertNotEquals(null, output.sourceStoreName, 'Should have source name');
        System.assertNotEquals(null, output.recommendedQty, 'Should have quantity');
        System.assertEquals(null, output.transferLogId, 'Should not have transfer log on dry-run');
    }

    /**
     * Test Case 2: Execution (confirm=true)
     * Verifies the action executes the transfer
     */
    @IsTest
    static void testExecutionAction() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Source Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Standard Medication' LIMIT 1];

        // Create inventory
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        // Prepare action input
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = true;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(1, outputs.size(), 'Should return one output');
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Should succeed');
        System.assertNotEquals(null, output.transferLogId, 'Should have transfer log on execution');
        System.assertNotEquals(null, output.recommendedQty, 'Should have quantity');
    }

    /**
     * Test Case 3: Default confirm value (null should default to false)
     * Verifies that null confirm defaults to false (dry-run)
     */
    @IsTest
    static void testDefaultConfirmValue() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Source Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Standard Medication' LIMIT 1];

        // Create inventory
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        // Prepare action input with null confirm
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = null;  // Explicitly set to null

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Should behave as dry-run
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(null, output.transferLogId, 'Null confirm should act as dry-run');
    }

    /**
     * Test Case 4: Schedule II Compliance in Action
     * Verifies Schedule II blocks propagate through the action
     */
    @IsTest
    static void testScheduleIIThroughAction() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Source Store' LIMIT 1];
        Medication__c scheduleIIMed = [SELECT Id FROM Medication__c WHERE Name = 'Schedule II Med' LIMIT 1];

        // Create inventory
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, scheduleIIMed.Id, 0, 30, 180
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, scheduleIIMed.Id, 100, 20, 150
        );

        // Prepare action input
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Assertions
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Schedule II should fail');
        System.assert(output.uhText.contains('Schedule II'), 'Should mention Schedule II');
        System.assertEquals(null, output.sourceStoreId, 'Should not have source for Schedule II');
    }

    /**
     * Test Case 5: Multiple Inputs (Batch)
     * Verifies the action handles multiple inputs correctly
     */
    @IsTest
    static void testMultipleInputs() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Source Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Standard Medication' LIMIT 1];

        // Create multiple inventory positions
        Inventory_Position__c target1 = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c target2 = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 5, 40, 85
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 300, 50, 120
        );

        // Prepare multiple action inputs
        InterStoreTransferAction.ActionInput input1 = new InterStoreTransferAction.ActionInput();
        input1.inventoryPositionId = target1.Id;
        input1.confirm = false;

        InterStoreTransferAction.ActionInput input2 = new InterStoreTransferAction.ActionInput();
        input2.inventoryPositionId = target2.Id;
        input2.confirm = false;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input1, input2 });
            Test.stopTest();
        }

        // Assertions
        System.assertEquals(2, outputs.size(), 'Should return two outputs');
        System.assertEquals(true, outputs[0].success, 'First should succeed');
        System.assertEquals(true, outputs[1].success, 'Second should succeed');
    }

    /**
     * Test Case 6: Invalid Inventory Position ID
     * Verifies error handling propagates through the action
     */
    @IsTest
    static void testInvalidIdThroughAction() {
        // Use fake ID
        Id fakeId = '001000000000000AAA';

        // Prepare action input
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = fakeId;
        input.confirm = false;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Assertions
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Should fail with invalid ID');
        System.assert(output.uhText.contains('Unable to locate'), 'Should indicate record not found');
    }

    /**
     * Test Case 7: No Suitable Source Through Action
     * Verifies distributor fallback propagates through the action
     */
    @IsTest
    static void testNoSuitableSourceThroughAction() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Target Store' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Standard Medication' LIMIT 1];

        // Create only target inventory (no source)
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );

        // Prepare action input
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        List<InterStoreTransferAction.ActionOutput> outputs;
        // Run as a non-admin user with the IST_Ops_User permission set
        User opsUser = ISTTestDataFactory.getOpsUser();
        System.runAs(opsUser) {
            Test.startTest();
            outputs =
                InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
            Test.stopTest();
        }

        // Assertions
        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Should fail with no source');
        System.assert(output.uhText.contains('No suitable source'), 'Should indicate no source');
        System.assert(output.uhText.contains('distributor'), 'Should recommend distributor');
    }
}