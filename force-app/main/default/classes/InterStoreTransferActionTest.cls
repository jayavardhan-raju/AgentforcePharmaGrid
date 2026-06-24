/**
 * @description Comprehensive test class for InterStoreTransferAction.
 *              Tests the Invocable Action wrapper and the Agentforce Grid
 *              refreshed quantity output contract.
 *
 *              The important Grid behavior tested here:
 *              - Salesforce.Quantity__c is updated in the database.
 *              - currentQuantity / updatedTargetQuantity are returned by the
 *                invocable action so Agentforce Grid can display the fresh value.
 *
 * @author      IST Team
 * @since       API v65.0
 */
@IsTest
private class InterStoreTransferActionTest {

    @TestSetup
    static void setupTestData() {
        ISTTestDataFactory.createStore(
            'Target Store',
            true,
            'DEA-001',
            true
        );
        ISTTestDataFactory.createStore(
            'Source Store',
            true,
            'DEA-002',
            true
        );

        ISTTestDataFactory.createMedication(
            'Standard Medication',
            'None',
            false
        );
        ISTTestDataFactory.createMedication(
            'Schedule II Med',
            'II',
            false
        );
    }

    /**
     * Dry-run should return recommendation details and current quantity,
     * but should not update inventory quantities or create a transfer log.
     */
    @IsTest
    static void testDryRunActionReturnsCurrentQuantityWithoutExecution() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            0,
            50,
            90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id,
            med.Id,
            200,
            50,
            120
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output.');

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Dry-run should succeed.');
        System.assertEquals('Recommended', output.transferStatus, 'Dry-run should return Recommended status.');
        System.assertNotEquals(null, output.uhText, 'Should have uhText.');
        System.assert(output.uhText.contains('Recommended Transfer Qty'), 'Should describe the recommendation.');
        System.assertEquals(sourceStore.Id, output.sourceStoreId, 'Should return source store ID.');
        System.assertEquals('Source Store', output.sourceStoreName, 'Should return source store name.');
        System.assertEquals(50, output.recommendedQty, 'Should recommend the target need.');
        System.assertEquals(0, output.transferredQty, 'Dry-run should not transfer units.');
        System.assertEquals(null, output.transferLogId, 'Dry-run should not create a transfer log.');
        System.assertEquals(target.Id, output.targetInventoryPositionId, 'Should return target inventory position ID.');
        System.assertEquals(source.Id, output.sourceInventoryPositionId, 'Should return source inventory position ID.');
        System.assertEquals(d(0), output.originalTargetQuantity, 'Should return original target quantity.');
        System.assertEquals(d(0), output.updatedTargetQuantity, 'Dry-run should return unchanged target quantity.');
        System.assertEquals(d(0), output.currentQuantity, 'Grid current quantity should remain unchanged on dry-run.');
        System.assertEquals(d(200), output.originalSourceQuantity, 'Should return original source quantity.');
        System.assertEquals(d(200), output.updatedSourceQuantity, 'Dry-run should return unchanged source quantity.');

        Inventory_Position__c refreshedTarget = [
            SELECT Quantity__c, Recommendation_Preview__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        Inventory_Position__c refreshedSource = [
            SELECT Quantity__c
            FROM Inventory_Position__c
            WHERE Id = :source.Id
        ];

        System.assertEquals(d(0), refreshedTarget.Quantity__c, 'Dry-run must not change target quantity.');
        System.assertEquals(d(200), refreshedSource.Quantity__c, 'Dry-run must not change source quantity.');
        System.assertNotEquals(
            null,
            refreshedTarget.Recommendation_Preview__c,
            'Dry-run should write recommendation preview for Grid display.'
        );
    }

    /**
     * Execution should update inventory and return post-DML refreshed quantities
     * for Agentforce Grid display.
     */
    @IsTest
    static void testExecutionActionReturnsUpdatedQuantities() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            0,
            50,
            90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id,
            med.Id,
            200,
            50,
            120
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = true;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output.');

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Execution should succeed.');
        System.assertEquals('Executed', output.transferStatus, 'Should return Executed status.');
        System.assertNotEquals(null, output.transferLogId, 'Execution should create a transfer log.');
        System.assertEquals(50, output.recommendedQty, 'Recommended quantity should equal target need.');
        System.assertEquals(50, output.transferredQty, 'Transferred quantity should be returned.');
        System.assertEquals(target.Id, output.targetInventoryPositionId, 'Should return target inventory position ID.');
        System.assertEquals(source.Id, output.sourceInventoryPositionId, 'Should return source inventory position ID.');
        System.assertEquals(d(0), output.originalTargetQuantity, 'Should return original target quantity.');
        System.assertEquals(d(50), output.updatedTargetQuantity, 'Should return refreshed target quantity.');
        System.assertEquals(d(50), output.currentQuantity, 'Grid current quantity should be the refreshed target quantity.');
        System.assertEquals(d(200), output.originalSourceQuantity, 'Should return original source quantity.');
        System.assertEquals(d(150), output.updatedSourceQuantity, 'Should return refreshed source quantity.');
        System.assert(output.uhText.contains('Updated target quantity: 50'), 'Message should include updated target quantity.');

        Inventory_Position__c refreshedTarget = [
            SELECT Quantity__c, Recommendation_Preview__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        Inventory_Position__c refreshedSource = [
            SELECT Quantity__c
            FROM Inventory_Position__c
            WHERE Id = :source.Id
        ];

        System.assertEquals(d(50), refreshedTarget.Quantity__c, 'Database target quantity should be updated.');
        System.assertEquals(d(150), refreshedSource.Quantity__c, 'Database source quantity should be updated.');
        System.assert(
            refreshedTarget.Recommendation_Preview__c.contains('Transfer completed'),
            'Target preview should show transfer completion.'
        );

        Transfer_Log__c transferLog = [
            SELECT Id, Quantity_Transferred__c, Transfer_Status__c, Inventory_Position__c
            FROM Transfer_Log__c
            WHERE Id = :output.transferLogId
        ];
        System.assertEquals(d(50), transferLog.Quantity_Transferred__c, 'Transfer log should record transferred quantity.');
        System.assertEquals('Completed', transferLog.Transfer_Status__c, 'Transfer log should be completed.');
        System.assertEquals(target.Id, transferLog.Inventory_Position__c, 'Transfer log should reference target inventory.');
    }

    /**
     * Null confirm should default to dry-run, not execution.
     */
    @IsTest
    static void testDefaultConfirmValueReturnsRecommendationOnly() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            0,
            50,
            90
        );
        ISTTestDataFactory.createInventory(
            sourceStore.Id,
            med.Id,
            200,
            50,
            120
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = null;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Default dry-run should succeed.');
        System.assertEquals('Recommended', output.transferStatus, 'Null confirm should behave as dry-run.');
        System.assertEquals(null, output.transferLogId, 'Null confirm should not create a transfer log.');
        System.assertEquals(0, output.transferredQty, 'Null confirm should not transfer units.');
        System.assertEquals(d(0), output.currentQuantity, 'Current quantity should remain original value.');

        Inventory_Position__c refreshedTarget = [
            SELECT Quantity__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        System.assertEquals(d(0), refreshedTarget.Quantity__c, 'Null confirm should not update target quantity.');
    }

    /**
     * Schedule II compliance block should return a blocked status and current
     * quantity so the Grid still has a deterministic display value.
     */
    @IsTest
    static void testScheduleIIThroughActionReturnsBlockedStatusAndCurrentQuantity() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c scheduleIIMed = getMedication('Schedule II Med');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            scheduleIIMed.Id,
            0,
            30,
            180
        );
        ISTTestDataFactory.createInventory(
            sourceStore.Id,
            scheduleIIMed.Id,
            100,
            20,
            150
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Schedule II should be blocked.');
        System.assertEquals('Blocked', output.transferStatus, 'Should return Blocked status.');
        System.assert(output.uhText.contains('Schedule II'), 'Should mention Schedule II.');
        System.assertEquals(null, output.sourceStoreId, 'Should not have source for Schedule II.');
        System.assertEquals(target.Id, output.targetInventoryPositionId, 'Should return target inventory ID.');
        System.assertEquals(d(0), output.currentQuantity, 'Blocked action should still return current target quantity.');
        System.assertEquals(d(0), output.updatedTargetQuantity, 'Blocked action should return unchanged target quantity.');

        Integer blockedLogs = [
            SELECT COUNT()
            FROM Transfer_Log__c
            WHERE Inventory_Position__c = :target.Id
            AND Transfer_Status__c = 'Blocked'
        ];
        System.assertEquals(1, blockedLogs, 'Should write a blocked compliance audit log.');
    }

    /**
     * Multiple dry-run inputs should each return their own current quantity and
     * recommendation output.
     */
    @IsTest
    static void testMultipleInputsReturnPerRowCurrentQuantities() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target1 = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            0,
            50,
            90
        );
        Inventory_Position__c target2 = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            5,
            40,
            85
        );
        ISTTestDataFactory.createInventory(
            sourceStore.Id,
            med.Id,
            300,
            50,
            120
        );

        InterStoreTransferAction.ActionInput input1 = new InterStoreTransferAction.ActionInput();
        input1.inventoryPositionId = target1.Id;
        input1.confirm = false;

        InterStoreTransferAction.ActionInput input2 = new InterStoreTransferAction.ActionInput();
        input2.inventoryPositionId = target2.Id;
        input2.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input1, input2 });
        Test.stopTest();

        System.assertEquals(2, outputs.size(), 'Should return two outputs.');
        System.assertEquals(true, outputs[0].success, 'First row should succeed.');
        System.assertEquals(true, outputs[1].success, 'Second row should succeed.');
        System.assertEquals('Recommended', outputs[0].transferStatus, 'First row should be recommended.');
        System.assertEquals('Recommended', outputs[1].transferStatus, 'Second row should be recommended.');
        System.assertEquals(d(0), outputs[0].currentQuantity, 'First row should return its own current quantity.');
        System.assertEquals(d(5), outputs[1].currentQuantity, 'Second row should return its own current quantity.');
        System.assertEquals(target1.Id, outputs[0].targetInventoryPositionId, 'First output should map to first input row.');
        System.assertEquals(target2.Id, outputs[1].targetInventoryPositionId, 'Second output should map to second input row.');
    }

    /**
     * Invalid Inventory Position IDs should return an error output instead of
     * throwing through the action.
     */
    @IsTest
    static void testInvalidIdThroughAction() {
        Id fakeId = '001000000000000AAA';

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = fakeId;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Should fail with invalid ID.');
        System.assertEquals('Error', output.transferStatus, 'Invalid ID should return Error status.');
        System.assert(output.uhText.contains('Unable to locate'), 'Should indicate record not found.');
        System.assertEquals(null, output.currentQuantity, 'No record means no current quantity can be returned.');
    }

    /**
     * Null Inventory Position ID should return an action-level error.
     */
    @IsTest
    static void testMissingInventoryPositionIdReturnsActionError() {
        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = null;
        input.confirm = true;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should return one output.');

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Missing ID should fail.');
        System.assertEquals('Error', output.transferStatus, 'Missing ID should return Error status.');
        System.assert(output.uhText.contains('Inventory Position ID is required'), 'Should explain the missing ID.');
    }

    /**
     * No suitable source should return fallback status and the unchanged current
     * quantity for the target row.
     */
    @IsTest
    static void testNoSuitableSourceThroughActionReturnsFallbackAndCurrentQuantity() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            0,
            50,
            90
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(false, output.success, 'Should fail with no source.');
        System.assertEquals('Fallback', output.transferStatus, 'No source should return Fallback status.');
        System.assert(output.uhText.contains('No suitable source'), 'Should indicate no source.');
        System.assert(output.uhText.contains('distributor'), 'Should recommend distributor.');
        System.assertEquals(target.Id, output.targetInventoryPositionId, 'Should return target row ID.');
        System.assertEquals(d(0), output.currentQuantity, 'Fallback should return unchanged current quantity.');
        System.assertEquals(d(0), output.updatedTargetQuantity, 'Fallback should return unchanged target quantity.');
    }

    /**
     * Healthy rows should not execute a transfer and should return their current
     * quantity for Grid display.
     */
    @IsTest
    static void testHealthyRowReturnsCurrentQuantityWithoutTransfer() {
        Pharmacy_Store__c targetStore = getStore('Target Store');
        Pharmacy_Store__c sourceStore = getStore('Source Store');
        Medication__c med = getMedication('Standard Medication');

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id,
            med.Id,
            200,
            50,
            90
        );
        Inventory_Position__c source = ISTTestDataFactory.createInventory(
            sourceStore.Id,
            med.Id,
            300,
            50,
            120
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = true;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        InterStoreTransferAction.ActionOutput output = outputs[0];
        System.assertEquals(true, output.success, 'Healthy row should complete without error.');
        System.assertEquals('Healthy', output.transferStatus, 'Healthy row should not execute transfer.');
        System.assertEquals(null, output.transferLogId, 'Healthy row should not create transfer log.');
        System.assertEquals(0, output.transferredQty, 'Healthy row should not transfer units.');
        System.assertEquals(target.Id, output.targetInventoryPositionId, 'Should return target row ID.');
        System.assertEquals(d(200), output.currentQuantity, 'Healthy row should return unchanged current quantity.');
        System.assertEquals(d(200), output.updatedTargetQuantity, 'Healthy row should return unchanged target quantity.');

        Inventory_Position__c refreshedTarget = [
            SELECT Quantity__c
            FROM Inventory_Position__c
            WHERE Id = :target.Id
        ];
        Inventory_Position__c refreshedSource = [
            SELECT Quantity__c
            FROM Inventory_Position__c
            WHERE Id = :source.Id
        ];

        System.assertEquals(d(200), refreshedTarget.Quantity__c, 'Healthy target should remain unchanged.');
        System.assertEquals(d(300), refreshedSource.Quantity__c, 'Healthy source should remain unchanged.');
    }

    private static Pharmacy_Store__c getStore(String name) {
        return [
            SELECT Id, Name
            FROM Pharmacy_Store__c
            WHERE Name = :name
            LIMIT 1
        ];
    }

    private static Medication__c getMedication(String name) {
        return [
            SELECT Id, Name
            FROM Medication__c
            WHERE Name = :name
            LIMIT 1
        ];
    }

    private static Decimal d(Integer value) {
        return Decimal.valueOf(String.valueOf(value));
    }
}
