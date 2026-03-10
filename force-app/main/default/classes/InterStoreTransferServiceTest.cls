/**
 * @description Test class for InterStoreTransferService.
 *              Covers: happy path, Schedule II block, no source fallback.
 *              Coverage target: 90%+
 */
@IsTest
private class InterStoreTransferServiceTest {

    // ─── Test Case 1: Happy Path — Recommend → Confirm → Execute ──────────────

    @IsTest
    static void testEvaluate_HappyPath_DryRun_ReturnsRecommendation() {
        // Arrange
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-TARGET-001', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Westside', true, 'DEA-SOURCE-001', true
        );
        Medication__c med = ISTTestDataFactory.createMedication('Mounjaro', 'None', true);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 60
        );
        Inventory_Position__c sourceInv = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 42
        );

        // Act — dry-run (confirm=false)
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, false);
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.success,
            'Dry-run should succeed when eligible source exists');
        System.assert(result.uhText.contains('Shall I proceed'),
            'Dry-run uhText must contain confirmation prompt');
        System.assert(result.uhText.contains('CVS Westside'),
            'uhText must name the source store');
        System.assertEquals('CVS Westside', result.sourceStoreName);
        System.assertNotEquals(null, result.recommendedQty);
        System.assert(result.recommendedQty > 0, 'Recommended qty should be positive');
        System.assertEquals(null, result.transferLogId,
            'No Transfer Log should be created on dry-run');
    }

    @IsTest
    static void testEvaluate_HappyPath_Execute_CreatesTransferLog() {
        // Arrange
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-TARGET-002', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Westside', true, 'DEA-SOURCE-002', true
        );
        Medication__c med = ISTTestDataFactory.createMedication('Mounjaro-Execute', 'None', true);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 60
        );
        Inventory_Position__c sourceInv = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 90
        );

        // Act — execute (confirm=true)
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, true);
        Test.stopTest();

        // Assert result
        System.assertEquals(true, result.success,
            'Execution should succeed when eligible source exists');
        System.assertNotEquals(null, result.transferLogId,
            'Transfer Log must be created on execution');
        System.assert(result.uhText.contains('Transfer Executed Successfully'),
            'uhText should confirm execution');

        // Assert Transfer Log
        Transfer_Log__c log = [
            SELECT Id, Transfer_Status__c, Quantity_Transferred__c
            FROM Transfer_Log__c WHERE Id = :result.transferLogId
        ];
        System.assertEquals('Completed', log.Transfer_Status__c);
        System.assert(log.Quantity_Transferred__c > 0);

        // Assert inventory was updated
        Inventory_Position__c updatedSource = [
            SELECT Quantity__c FROM Inventory_Position__c WHERE Id = :sourceInv.Id
        ];
        System.assert(updatedSource.Quantity__c < 200,
            'Source inventory should have decreased');
    }

    // ─── Test Case 2: Schedule II Block ───────────────────────────────────────

    @IsTest
    static void testEvaluate_ScheduleII_DryRun_HardStop() {
        // Arrange
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-TARGET-003', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Westside', true, 'DEA-SOURCE-003', true
        );
        // Schedule II medication — Adderall
        Medication__c adderall = ISTTestDataFactory.createMedication('Adderall', 'II', false);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, adderall.Id, 0, 30, 90
        );
        Inventory_Position__c sourceInv = ISTTestDataFactory.createInventory(
            sourceStore.Id, adderall.Id, 200, 30, 90
        );

        // Act
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, false);
        Test.stopTest();

        // Assert: hard stop
        System.assertEquals(false, result.success,
            'Schedule II must return success=false');
        System.assert(result.uhText.contains('Schedule II'),
            'uhText must mention Schedule II');
        System.assert(result.uhText.contains('DEA Form 222'),
            'uhText must reference DEA Form 222');
        System.assert(!result.uhText.contains('Shall I proceed'),
            'Schedule II must NEVER include a confirmation prompt');
        System.assertEquals(null, result.sourceStoreId,
            'No source store should be surfaced for Schedule II');

        // Assert compliance block log was created
        List<Transfer_Log__c> logs = [
            SELECT Id, Transfer_Status__c FROM Transfer_Log__c
            WHERE Medication__c = :adderall.Id
        ];
        System.assert(!logs.isEmpty(), 'Compliance block log must be written');
        System.assertEquals('Blocked', logs[0].Transfer_Status__c);
    }

    @IsTest
    static void testEvaluate_ScheduleII_ConfirmTrue_StillBlocked() {
        // Verify that confirm=true does NOT bypass Schedule II block
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-T004', true
        );
        Medication__c adderall = ISTTestDataFactory.createMedication('Adderall-Confirm', 'II', false);
        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, adderall.Id, 0, 30, 90
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, true);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Schedule II must block even when confirm=true');

        // Ensure no Completed transfer logs
        List<Transfer_Log__c> completed = [
            SELECT Id FROM Transfer_Log__c
            WHERE Medication__c = :adderall.Id AND Transfer_Status__c = 'Completed'
        ];
        System.assert(completed.isEmpty(), 'No Completed log should exist for Schedule II');
    }

    // ─── Test Case 3: No Suitable Source Found ────────────────────────────────

    @IsTest
    static void testEvaluate_NoSuitableSource_ReturnsFallback() {
        // Arrange — Mounjaro 5mg, no other store has surplus
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-T005', true
        );
        Medication__c mounjaro5mg = ISTTestDataFactory.createMedication('Mounjaro 5mg', 'None', true);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, mounjaro5mg.Id, 0, 60, 90
        );
        // No source inventory record created — network has nothing

        // Act
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, false);
        Test.stopTest();

        // Assert
        System.assertEquals(false, result.success,
            'No source should return success=false');
        System.assert(result.uhText.contains('No suitable source store found'),
            'uhText must state no source found');
        System.assert(result.uhText.contains('distributor'),
            'uhText must recommend distributor as next action');
        System.assert(!result.uhText.contains('Shall I proceed'),
            'No source fallback must NOT include confirmation prompt');
    }

    @IsTest
    static void testEvaluate_NoSuitableSource_ColdChainMismatch() {
        // Arrange — target cold-chain needed but source store not capable
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-T006', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Eastside', false, 'DEA-S006', true  // no cold chain
        );
        Medication__c med = ISTTestDataFactory.createMedication('Mounjaro 5mg Cold', 'None', true);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 60, 90
        );
        Inventory_Position__c sourceInv = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 300, 50, 90
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, false);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Cold-chain mismatch should result in no eligible source');
    }

    // ─── Edge Cases ───────────────────────────────────────────────────────────

    @IsTest
    static void testEvaluate_NullId_ReturnsErrorGracefully() {
        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(null, false);
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(String.isNotBlank(result.uhText));
    }

    @IsTest
    static void testEvaluate_ExpiredSourceStock_Excluded() {
        // Source stock expires in < 30 days — should be excluded
        Pharmacy_Store__c targetStore = ISTTestDataFactory.createStore(
            'CVS Downtown', true, 'DEA-T007', true
        );
        Pharmacy_Store__c sourceStore = ISTTestDataFactory.createStore(
            'CVS Westside', true, 'DEA-S007', true
        );
        Medication__c med = ISTTestDataFactory.createMedication('Mounjaro Expiring', 'None', true);

        Inventory_Position__c targetInv = ISTTestDataFactory.createInventory(
            targetStore.Id, med.Id, 0, 50, 90
        );
        Inventory_Position__c sourceInv = ISTTestDataFactory.createInventory(
            sourceStore.Id, med.Id, 200, 50, 10 // expires in 10 days — below 30 day threshold
        );

        Test.startTest();
        InterStoreTransferService.TransferResult result =
            InterStoreTransferService.evaluate(targetInv.Id, false);
        Test.stopTest();

        System.assertEquals(false, result.success,
            'Source with < 30 days to expiry should be excluded');
    }
}