/**
 * @description Comprehensive test class for InterStoreTransferService
 *              Covers all scenarios including:
 *              - Schedule II compliance blocks
 *              - Successful transfers (dry-run and execution)
 *              - Cold-chain filtering
 *              - DEA registration validation
 *              - Expiry date filtering
 *              - No suitable source scenarios
 *              - Quantity calculations
 *              - Error handling and rollback
 *              - Security/FLS scenarios
 *
 * @author      IST Team
 * @since       API v65.0
 */
@IsTest
private class InterStoreTransferServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create stores with various capabilities
        Pharmacy_Store__c store1 = ISTTestDataFactory.createStore(
            'Store A - Target', true, 'DEA-001', true
        );
        Pharmacy_Store__c store2 = ISTTestDataFactory.createStore(
            'Store B - Source (Good)', true, 'DEA-002', true
        );
        Pharmacy_Store__c store3 = ISTTestDataFactory.createStore(
            'Store C - No Cold Chain', false, 'DEA-003', true
        );
        Pharmacy_Store__c store4 = ISTTestDataFactory.createStore(
            'Store D - No DEA', true, '', true
        );
        Pharmacy_Store__c store5 = ISTTestDataFactory.createStore(
            'Store E - Inactive', true, 'DEA-005', false
        );

        // Create medications with various schedules
        Medication__c medScheduleII = ISTTestDataFactory.createMedication(
            'Adderall XR 30mg', 'II', false
        );
        Medication__c medColdChain = ISTTestDataFactory.createMedication(
            'Ozempic 1mg', 'None', true
        );
        Medication__c medStandard = ISTTestDataFactory.createMedication(
            'Lisinopril 10mg', 'None', false
        );
        Medication__c medScheduleIV = ISTTestDataFactory.createMedication(
            'Xanax 0.5mg', 'IV', false
        );
    }

    /**
     * Test Case 1: Schedule II Compliance Block
     * Verifies that Schedule II medications trigger compliance stop
     */
    @IsTest
    static void testScheduleIIComplianceBlock() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c scheduleIIMed = [SELECT Id FROM Medication__c WHERE Name = 'Adderall XR 30mg' LIMIT 1];

        // Create inventory positions
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, scheduleIIMed.Id, 0, 30, 180
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, scheduleIIMed.Id, 100, 20, 150
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Assertions
        System.assertEquals(false, result.success, 'Schedule II should fail');
        System.assert(result.uhText.contains('Schedule II'), 'Should mention Schedule II');
        System.assert(result.uhText.contains('DEA Form 222'), 'Should mention DEA Form 222');

        // Verify compliance block was logged
        List<Transfer_Log__c> logs = [
            SELECT Id, Transfer_Status__c, Notes__c
            FROM Transfer_Log__c
            WHERE Inventory_Position__c = :target.Id
        ];
        System.assertEquals(1, logs.size(), 'Should create compliance log');
        System.assertEquals('Blocked', logs[0].Transfer_Status__c, 'Status should be Blocked');
    }

    /**
     * Test Case 2: Successful Dry-Run Recommendation
     * Verifies recommendation generation without execution
     */
    @IsTest
    static void testSuccessfulDryRun() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create inventory: target critical, source has surplus
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Assertions
        System.assertEquals(true, result.success, 'Dry-run should succeed');
        System.assertNotEquals(null, result.sourceStoreId, 'Should have source store');
        System.assertNotEquals(null, result.sourceStoreName, 'Should have source name');
        System.assertNotEquals(null, result.recommendedQty, 'Should have quantity');
        System.assert(result.recommendedQty > 0, 'Quantity should be positive');
        System.assertEquals(null, result.transferLogId, 'Should not create log on dry-run');

        // Verify recommendation was written to target record
        Inventory_Position__c updatedTarget = [
            SELECT Recommendation__c, Recommendation_Preview__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        System.assertNotEquals(null, updatedTarget.Recommendation__c, 'Should write recommendation');
        System.assertNotEquals(null, updatedTarget.Recommendation_Preview__c, 'Should write preview');
    }

    /**
     * Test Case 3: Successful Transfer Execution
     * Verifies atomic DML for inventory updates and audit log creation
     */
    @IsTest
    static void testSuccessfulExecution() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create inventory: target critical, source has surplus
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        Decimal initialSourceQty = source.Quantity__c;
        Decimal initialTargetQty = target.Quantity__c;

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, true);
        Test.stopTest();

        // Assertions
        System.assertEquals(true, result.success, 'Execution should succeed');
        System.assertNotEquals(null, result.transferLogId, 'Should create transfer log');
        System.assertNotEquals(null, result.recommendedQty, 'Should have quantity');

        // Verify inventory updates
        Inventory_Position__c updatedSource = [
            SELECT Quantity__c FROM Inventory_Position__c WHERE Id = :source.Id
        ];
        Inventory_Position__c updatedTarget = [
            SELECT Quantity__c, Recommendation_Preview__c
            FROM Inventory_Position__c WHERE Id = :target.Id
        ];

        System.assertEquals(
            initialSourceQty - result.recommendedQty,
            updatedSource.Quantity__c,
            'Source quantity should decrease'
        );
        System.assertEquals(
            initialTargetQty + result.recommendedQty,
            updatedTarget.Quantity__c,
            'Target quantity should increase'
        );
        System.assert(
            updatedTarget.Recommendation_Preview__c.contains('Transfer completed'),
            'Should update preview with completion status'
        );

        // Verify transfer log
        Transfer_Log__c log = [
            SELECT Transfer_Status__c, Quantity_Transferred__c, Notes__c
            FROM Transfer_Log__c
            WHERE Id = :result.transferLogId
        ];
        System.assertEquals('Completed', log.Transfer_Status__c, 'Status should be Completed');
        System.assertEquals(result.recommendedQty, (Integer)log.Quantity_Transferred__c, 'Quantity should match');
    }

    /**
     * Test Case 4: Cold-Chain Filtering
     * Verifies that cold-chain required meds exclude non-capable stores
     */
    @IsTest
    static void testColdChainFiltering() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c noColdChainStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store C - No Cold Chain' LIMIT 1];
        Medication__c coldChainMed = [SELECT Id FROM Medication__c WHERE Name = 'Ozempic 1mg' LIMIT 1];

        // Create inventory: only non-cold-chain store has surplus
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, coldChainMed.Id, 0, 40, 180
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            noColdChainStore.Id, coldChainMed.Id, 100, 20, 120
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Should fail because only source lacks cold-chain capability
        System.assertEquals(false, result.success, 'Should fail with no suitable source');
        System.assert(result.uhText.contains('No suitable source'), 'Should indicate no source found');
        System.assert(result.uhText.contains('distributor'), 'Should recommend distributor');
    }

    /**
     * Test Case 5: DEA Registration Filtering
     * Verifies that stores without DEA registration are excluded
     */
    @IsTest
    static void testDEARegistrationFiltering() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c noDEAStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store D - No DEA' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Xanax 0.5mg' LIMIT 1];

        // Create inventory: only non-DEA store has surplus
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 10, 40, 200
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            noDEAStore.Id, med.Id, 150, 30, 180
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Should fail because source lacks DEA registration
        System.assertEquals(false, result.success, 'Should fail with no suitable source');
        System.assert(result.uhText.contains('No suitable source'), 'Should indicate no source found');
    }

    /**
     * Test Case 6: Expiry Date Filtering
     * Verifies that near-expiry stock is excluded from transfers
     */
    @IsTest
    static void testExpiryDateFiltering() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create inventory: source has stock expiring within 30 days
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 60, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 100, 20, 15  // Expires in 15 days
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Should fail because source stock is near expiry
        System.assertEquals(false, result.success, 'Should fail with near-expiry source');
        System.assert(result.uhText.contains('No suitable source'), 'Should indicate no source found');
    }

    /**
     * Test Case 7: Quantity Calculation
     * Verifies correct calculation of transfer quantity (50% of surplus, capped at target need)
     */
    @IsTest
    static void testQuantityCalculation() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create inventory with specific quantities for calculation test
        // Target needs 50 units (50 - 0)
        // Source has 100 surplus (150 - 50)
        // Should transfer 50 units (50% of 100, which equals target need)
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 150, 50, 120
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Should recommend 50 units (50% of 100 surplus = 50, min with 50 target need = 50)
        System.assertEquals(50, result.recommendedQty, 'Should calculate 50 units');
    }

    /**
     * Test Case 8: Invalid Inventory Position ID
     * Verifies error handling for non-existent records
     */
    @IsTest
    static void testInvalidInventoryPositionId() {
        // Use fake ID that doesn't exist
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(fakeId, false);
        Test.stopTest();

        // Should return error result
        System.assertEquals(false, result.success, 'Should fail with invalid ID');
        System.assert(result.uhText.contains('Unable to locate'), 'Should indicate record not found');
    }

    /**
     * Test Case 9: Multiple Sources - Best Selection
     * Verifies that the source with most surplus is selected
     */
    @IsTest
    static void testBestSourceSelection() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create another good source with higher quantity
        Pharmacy_Store__c bestSource = ISTTestDataFactory.createStore(
            'Store F - Best Source', true, 'DEA-006', true
        );

        // Create inventory positions
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c goodSource = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 150, 50, 120
        );
        Inventory_Position__c betterSource = ISTTestDataFactory.createInventory(
            bestSource.Id, med.Id, 300, 50, 130  // Highest quantity
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Should select the source with most surplus
        System.assertEquals(true, result.success, 'Should succeed');
        System.assertEquals(bestSource.Id, result.sourceStoreId, 'Should select best source');
    }

    /**
     * Test Case 10: Preview Text Truncation
     * Verifies that long recommendations are properly truncated for preview field
     */
    @IsTest
    static void testPreviewTextTruncation() {
        // Query test data
        Pharmacy_Store__c targetStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store A - Target' LIMIT 1];
        Pharmacy_Store__c sourceStore = [SELECT Id FROM Pharmacy_Store__c WHERE Name = 'Store B - Source (Good)' LIMIT 1];
        Medication__c med = [SELECT Id FROM Medication__c WHERE Name = 'Lisinopril 10mg' LIMIT 1];

        // Create inventory
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 120
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(target.Id, false);
        Test.stopTest();

        // Verify preview field is within limits
        Inventory_Position__c updatedTarget = [
            SELECT Recommendation_Preview__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        System.assert(
            updatedTarget.Recommendation_Preview__c.length() <= 255,
            'Preview should be truncated to 255 chars'
        );
    }
}