/**
 * @description Test class for InterStoreTransferAction (Invocable layer).
 *              Validates input/output wiring to service layer.
 */
@IsTest
private class InterStoreTransferActionTest {

    @IsTest
    static void testAction_HappyPath_DryRun_ReturnsOutput() {
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-ACT-T01', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Westside', true, 'DEA-ACT-S01', true
        );
        Medication__c med = ISTTestDataFactory.createMedication('Mounjaro-Action', 'None', true);

        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 60
        );
        ISTTestDataFactory.createInventory(sourceStore.Id, med.Id, 200, 50, 90);

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].success);
        System.assertNotEquals(null, outputs[0].uhText);
        System.assertNotEquals(null, outputs[0].sourceStoreName);
        System.assert(outputs[0].recommendedQty > 0);
    }

    @IsTest
    static void testAction_ScheduleII_ReturnsComplianceBlock() {
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-ACT-T02', true
        );
        Medication__c adderall = ISTTestDataFactory.createMedication('Adderall-Act', 'II', false);
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, adderall.Id, 0, 30, 90
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = false;

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(false, outputs[0].success);
        System.assert(outputs[0].uhText.contains('Schedule II'));
    }

    @IsTest
    static void testAction_NullConfirm_DefaultsToFalse() {
        // confirm=null should default to false (dry-run)
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS', true, 'DEA-ACT-T03', true
        );
        Medication__c med = ISTTestDataFactory.createMedication('Med-NullConfirm', 'None', false);
        Inventory_Position__c target = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 10, 60
        );

        InterStoreTransferAction.ActionInput input = new InterStoreTransferAction.ActionInput();
        input.inventoryPositionId = target.Id;
        input.confirm = null; // explicit null

        Test.startTest();
        List<InterStoreTransferAction.ActionOutput> outputs =
            InterStoreTransferAction.execute(new List<InterStoreTransferAction.ActionInput>{ input });
        Test.stopTest();

        // No Transfer_Log__c should exist (dry-run)
        List<Transfer_Log__c> logs = [
            SELECT Id FROM Transfer_Log__c WHERE Transfer_Status__c = 'Completed'
            AND Inventory_Position__c = :target.Id
        ];
        System.assert(logs.isEmpty(), 'Null confirm must not execute transfer');
    }
}