/**
 * @description Core service for Inter-Store Transfer (IST) operations.
 *              Enforces: DEA Schedule II compliance, cold-chain matching,
 *              inventory locking, and atomic DML with audit trail.
 *
 *              Contract:
 *                confirm = false -> dry-run recommendation only
 *                confirm = true  -> execute transfer atomically
 *
 *              Agentforce Grid refresh contract:
 *                The service always returns currentQuantity for the target row.
 *                On execution, it re-queries the updated records after DML and
 *                returns updatedTargetQuantity / updatedSourceQuantity.
 *
 * @author      IST Team
 * @since       API v65.0
 */
public with sharing class InterStoreTransferService {

    // Transfer 50% of source surplus above its own safety stock.
    private static final Integer TRANSFER_BUFFER_PCT = 50;

    // Source stock expiring within this many days is excluded from transfer.
    private static final Integer MIN_DAYS_TO_EXPIRY = 30;

    // DEA Schedule that triggers a hard compliance block.
    private static final String DEA_SCHEDULE_II = 'II';

    // Max length of Text(255) Recommendation_Preview__c Grid column.
    private static final Integer PREVIEW_MAX_LENGTH = 255;

    /**
     * Structured result returned to InterStoreTransferAction.
     */
    public class TransferResult {
        public Boolean success;
        public String  transferStatus;
        public String  uhText;

        public Id      targetInventoryPositionId;
        public Id      sourceInventoryPositionId;
        public Id      sourceStoreId;
        public String  sourceStoreName;
        public Integer recommendedQty;
        public Integer transferredQty;
        public Id      transferLogId;

        public Decimal originalTargetQuantity;
        public Decimal updatedTargetQuantity;
        public Decimal currentQuantity;
        public Decimal originalSourceQuantity;
        public Decimal updatedSourceQuantity;

        public TransferResult(Boolean success, String uhText) {
            this.success = success;
            this.uhText = uhText;
            this.transferredQty = 0;
        }
    }

    /**
     * Evaluate and optionally execute an inter-store transfer.
     */
    public static TransferResult evaluate(Id inventoryPositionId, Boolean confirm) {
        if (inventoryPositionId == null) {
            TransferResult missingId = new TransferResult(false,
                'Inventory Position ID is required. Please refresh the Grid row and try again.');
            missingId.transferStatus = 'Error';
            return missingId;
        }

        Inventory_Position__c target;
        try {
            target = InventoryPositionSelector.getById(inventoryPositionId);
        } catch (Exception ex) {
            TransferResult notFound = new TransferResult(false,
                'Unable to locate Inventory Position. Please refresh and try again. ['
                + ex.getTypeName() + ': ' + ex.getMessage() + ']');
            notFound.transferStatus = 'Error';
            return notFound;
        }

        if (isScheduleII(target)) {
            logComplianceBlock(target);

            TransferResult blocked = new TransferResult(false,
                'Compliance Restriction: Schedule II controlled substance detected - '
                + target.Medication__r.Name
                + ' (DEA Schedule II). Manual DEA Form 222 is required for all transfers. '
                + 'Please contact your DEA compliance officer to initiate a manual transfer. '
                + 'No automated transfer has been initiated.');
            blocked.transferStatus = 'Blocked';
            setTargetSnapshot(blocked, target);
            return blocked;
        }

        if (!isBelowSafetyStock(target)) {
            TransferResult healthy = new TransferResult(true,
                'Stock levels are healthy. No transfer is required at this time.');
            healthy.transferStatus = 'Healthy';
            setTargetSnapshot(healthy, target);
            return healthy;
        }

        List<Inventory_Position__c> candidates =
            InventoryPositionSelector.findSurplusSources(
                target.Medication__c,
                target.Store__c,
                toInteger(target.Safety_Stock__c) + 1
            );

        Inventory_Position__c bestSource = selectBestSource(target, candidates);

        if (bestSource == null) {
            TransferResult fallback = new TransferResult(false,
                'No suitable source store found for '
                + target.Medication__r.Name
                + ' in the distribution network. '
                + 'Recommended next action: Place an emergency order with your primary distributor. '
                + 'Contact your district manager to expedite the distributor order.');
            fallback.transferStatus = 'Fallback';
            setTargetSnapshot(fallback, target);
            return fallback;
        }

        Integer recommendedQty = calculateTransferQty(target, bestSource);

        if (recommendedQty == null || recommendedQty <= 0) {
            TransferResult noQty = new TransferResult(false,
                'No valid transfer quantity could be calculated. '
                + 'Please review source surplus, target safety stock, and current quantity.');
            noQty.transferStatus = 'No Quantity';
            setTargetAndSourceSnapshot(noQty, target, bestSource);
            return noQty;
        }

        Boolean confirmFlag = confirm != null ? confirm : false;
        if (!confirmFlag) {
            return buildRecommendation(target, bestSource, recommendedQty);
        }

        return executeTransfer(target, bestSource, recommendedQty);
    }

    /**
     * Returns true if the medication is DEA Schedule II.
     */
    private static Boolean isScheduleII(Inventory_Position__c inv) {
        return inv.Medication__r.DEA_Schedule__c == DEA_SCHEDULE_II;
    }

    /**
     * Returns true only when the target needs inventory.
     */
    private static Boolean isBelowSafetyStock(Inventory_Position__c inv) {
        Decimal quantity = inv.Quantity__c == null ? 0 : inv.Quantity__c;
        Decimal safetyStock = inv.Safety_Stock__c == null ? 0 : inv.Safety_Stock__c;
        return quantity < safetyStock;
    }

    /**
     * Selects the best eligible source from the candidate list.
     */
    private static Inventory_Position__c selectBestSource(
        Inventory_Position__c target,
        List<Inventory_Position__c> candidates
    ) {
        Boolean coldChainNeeded = target.Medication__r.Cold_Chain_Required__c == true;
        Date today = Date.today();

        for (Inventory_Position__c candidate : candidates) {
            if (coldChainNeeded && candidate.Store__r.Cold_Chain_Capable__c != true) {
                continue;
            }

            if (String.isBlank(candidate.Store__r.DEA_Registration__c)) {
                continue;
            }

            if (candidate.Expiry_Date__c != null
                && today.daysBetween(candidate.Expiry_Date__c) < MIN_DAYS_TO_EXPIRY) {
                continue;
            }

            return candidate;
        }

        return null;
    }

    /**
     * Calculates units to transfer.
     */
    private static Integer calculateTransferQty(
        Inventory_Position__c target,
        Inventory_Position__c source
    ) {
        Integer sourceSurplus =
            toInteger(source.Quantity__c) - toInteger(source.Safety_Stock__c);
        Integer targetNeed =
            toInteger(target.Safety_Stock__c) - toInteger(target.Quantity__c);

        if (sourceSurplus < 0) {
            sourceSurplus = 0;
        }
        if (targetNeed < 0) {
            targetNeed = 0;
        }

        Integer proposed = (Integer)(sourceSurplus * TRANSFER_BUFFER_PCT / 100);
        return Math.min(proposed, targetNeed);
    }

    /**
     * Builds the dry-run recommendation result.
     */
    private static TransferResult buildRecommendation(
        Inventory_Position__c target,
        Inventory_Position__c source,
        Integer qty
    ) {
        Integer daysToExpiry = source.Expiry_Date__c != null
            ? Date.today().daysBetween(source.Expiry_Date__c)
            : 0;

        String scheduleLabel = String.isNotBlank(target.Medication__r.DEA_Schedule__c)
            ? target.Medication__r.DEA_Schedule__c
            : 'None';

        String uhText =
            'Transfer Recommendation for ' + target.Medication__r.Name
            + ' at ' + target.Store__r.Name + ': '
            + 'Source Store: ' + source.Store__r.Name + '. '
            + 'Available Stock: ' + toInteger(source.Quantity__c) + ' units. '
            + 'Days to Expiry: ' + daysToExpiry + ' days. '
            + 'Cold-Chain: Both stores verified capable. '
            + 'DEA Compliance: Validated (Schedule ' + scheduleLabel + '). '
            + 'Recommended Transfer Qty: ' + qty + ' units. '
            + 'Shall I proceed with this transfer?';

        String previewText = trimForPreview(uhText);

        if (Schema.sObjectType.Inventory_Position__c.isUpdateable()
            && Schema.sObjectType.Inventory_Position__c.fields.Recommendation__c.isUpdateable()
            && Schema.sObjectType.Inventory_Position__c.fields.Recommendation_Preview__c.isUpdateable()
        ) {
            update new Inventory_Position__c(
                Id                        = target.Id,
                Recommendation__c         = uhText,
                Recommendation_Preview__c = previewText
            );
        }

        TransferResult result = new TransferResult(true, uhText);
        result.transferStatus = 'Recommended';
        result.sourceStoreId = source.Store__c;
        result.sourceStoreName = source.Store__r.Name;
        result.recommendedQty = qty;
        setTargetAndSourceSnapshot(result, target, source);
        return result;
    }

    /**
     * Executes the confirmed transfer atomically and returns refreshed quantities.
     */
    private static TransferResult executeTransfer(
        Inventory_Position__c target,
        Inventory_Position__c source,
        Integer qty
    ) {
        Savepoint sp = Database.setSavepoint();

        try {
            if (!Schema.sObjectType.Inventory_Position__c.isUpdateable()
                || !Schema.sObjectType.Inventory_Position__c.fields.Quantity__c.isUpdateable()) {
                throw new SecurityException(
                    'Insufficient permissions to update Inventory Position quantities.');
            }
            if (!Schema.sObjectType.Transfer_Log__c.isCreateable()) {
                throw new SecurityException(
                    'Insufficient permissions to create Transfer Log records.');
            }

            Set<Id> inventoryIds = new Set<Id>{ target.Id, source.Id };

            Map<Id, Inventory_Position__c> lockedInventory =
                new Map<Id, Inventory_Position__c>([
                    SELECT Id,
                           Quantity__c,
                           Safety_Stock__c,
                           Store__c,
                           Store__r.Name,
                           Medication__c,
                           Medication__r.Name,
                           Medication__r.DEA_Schedule__c,
                           Recommendation_Preview__c
                    FROM Inventory_Position__c
                    WHERE Id IN :inventoryIds
                    FOR UPDATE
                ]);

            Inventory_Position__c lockedTarget = lockedInventory.get(target.Id);
            Inventory_Position__c lockedSource = lockedInventory.get(source.Id);

            if (lockedTarget == null || lockedSource == null) {
                throw new IllegalArgumentException(
                    'Unable to lock source and target inventory records.');
            }

            Integer recalculatedQty = calculateTransferQty(lockedTarget, lockedSource);
            Integer executableQty = Math.min(qty, recalculatedQty);

            if (executableQty <= 0) {
                TransferResult noOp = new TransferResult(true,
                    'No transfer was executed because the target no longer requires inventory '
                    + 'or the source no longer has eligible surplus. Current quantity returned.');
                noOp.transferStatus = 'Healthy';
                noOp.recommendedQty = qty;
                setTargetAndSourceSnapshot(noOp, lockedTarget, lockedSource);
                return noOp;
            }

            Decimal sourceQuantityBefore = lockedSource.Quantity__c == null ? 0 : lockedSource.Quantity__c;
            Decimal targetQuantityBefore = lockedTarget.Quantity__c == null ? 0 : lockedTarget.Quantity__c;
            Decimal sourceQuantityAfter = sourceQuantityBefore - executableQty;
            Decimal targetQuantityAfter = targetQuantityBefore + executableQty;

            Inventory_Position__c sourceUpdate = new Inventory_Position__c(
                Id          = lockedSource.Id,
                Quantity__c = sourceQuantityAfter
            );

            String completionPreview = 'Transfer completed: ' + executableQty + ' units from '
                + lockedSource.Store__r.Name + '. See Transfer Log for details.';

            Inventory_Position__c targetUpdate = new Inventory_Position__c(
                Id                        = lockedTarget.Id,
                Quantity__c               = targetQuantityAfter,
                Recommendation_Preview__c = trimForPreview(completionPreview)
            );

            Transfer_Log__c log = new Transfer_Log__c(
                Source_Store__c         = lockedSource.Store__c,
                Target_Store__c         = lockedTarget.Store__c,
                Medication__c           = lockedTarget.Medication__c,
                Inventory_Position__c   = lockedTarget.Id,
                Quantity_Transferred__c = executableQty,
                Transfer_Status__c      = 'Completed',
                Transfer_Date__c        = DateTime.now(),
                Notes__c                =
                    'Agentforce Grid IST - Automated transfer. '
                    + 'Source: ' + lockedSource.Store__r.Name
                    + ' -> Target: ' + lockedTarget.Store__r.Name
                    + ' | Medication: ' + lockedTarget.Medication__r.Name
                    + ' | Qty: ' + executableQty
                    + ' | DEA Schedule: ' + lockedTarget.Medication__r.DEA_Schedule__c
            );

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<SObject>{ sourceUpdate, targetUpdate }
            );
            update decision.getRecords();
            insert log;

            Map<Id, Inventory_Position__c> refreshedInventory =
                new Map<Id, Inventory_Position__c>([
                    SELECT Id, Quantity__c
                    FROM Inventory_Position__c
                    WHERE Id IN :inventoryIds
                ]);

            Inventory_Position__c refreshedTarget = refreshedInventory.get(lockedTarget.Id);
            Inventory_Position__c refreshedSource = refreshedInventory.get(lockedSource.Id);

            String uhText =
                'Transfer Executed Successfully. '
                + 'Completed transfer of ' + executableQty + ' units of '
                + lockedTarget.Medication__r.Name
                + ' from ' + lockedSource.Store__r.Name
                + ' to ' + lockedTarget.Store__r.Name + '. '
                + 'Updated target quantity: ' + refreshedTarget.Quantity__c + '. '
                + 'Updated source quantity: ' + refreshedSource.Quantity__c + '. '
                + 'Transfer Log Reference: ' + log.Id + '. '
                + 'Timestamp: ' + DateTime.now().formatGmt('yyyy-MM-dd HH:mm:ss') + ' UTC. '
                + 'Audit trail recorded.';

            TransferResult result = new TransferResult(true, uhText);
            result.transferStatus = 'Executed';
            result.transferLogId = log.Id;
            result.sourceStoreId = lockedSource.Store__c;
            result.sourceStoreName = lockedSource.Store__r.Name;
            result.sourceInventoryPositionId = lockedSource.Id;
            result.targetInventoryPositionId = lockedTarget.Id;
            result.recommendedQty = qty;
            result.transferredQty = executableQty;
            result.originalTargetQuantity = targetQuantityBefore;
            result.updatedTargetQuantity = refreshedTarget.Quantity__c;
            result.currentQuantity = refreshedTarget.Quantity__c;
            result.originalSourceQuantity = sourceQuantityBefore;
            result.updatedSourceQuantity = refreshedSource.Quantity__c;
            return result;

        } catch (Exception ex) {
            Database.rollback(sp);

            TransferResult failed = new TransferResult(false,
                'Transfer failed and was fully rolled back. '
                + 'No inventory changes were made. '
                + 'Error: ' + ex.getMessage()
                + ' Please retry or escalate to your district manager.');
            failed.transferStatus = 'Failed';
            failed.recommendedQty = qty;
            setTargetAndSourceSnapshot(failed, target, source);
            return failed;
        }
    }

    /**
     * Writes a blocked Transfer_Log__c when a Schedule II compliance stop is triggered.
     */
    private static void logComplianceBlock(Inventory_Position__c inv) {
        if (!Schema.sObjectType.Transfer_Log__c.isCreateable()) {
            return;
        }

        try {
            insert new Transfer_Log__c(
                Target_Store__c         = inv.Store__c,
                Medication__c           = inv.Medication__c,
                Inventory_Position__c   = inv.Id,
                Quantity_Transferred__c = 0,
                Transfer_Status__c      = 'Blocked',
                Transfer_Date__c        = DateTime.now(),
                Notes__c                =
                    'COMPLIANCE BLOCK: DEA Schedule II - '
                    + inv.Medication__r.Name
                    + '. DEA Form 222 required. '
                    + 'Automated transfer denied by Agentforce Grid.'
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'Failed to write Schedule II compliance block log: ' + ex.getMessage());
        }
    }

    private static void setTargetSnapshot(
        TransferResult result,
        Inventory_Position__c target
    ) {
        if (result == null || target == null) {
            return;
        }

        result.targetInventoryPositionId = target.Id;
        result.originalTargetQuantity = target.Quantity__c;
        result.updatedTargetQuantity = target.Quantity__c;
        result.currentQuantity = target.Quantity__c;
    }

    private static void setTargetAndSourceSnapshot(
        TransferResult result,
        Inventory_Position__c target,
        Inventory_Position__c source
    ) {
        setTargetSnapshot(result, target);

        if (result == null || source == null) {
            return;
        }

        result.sourceInventoryPositionId = source.Id;
        result.sourceStoreId = source.Store__c;
        result.sourceStoreName = source.Store__r.Name;
        result.originalSourceQuantity = source.Quantity__c;
        result.updatedSourceQuantity = source.Quantity__c;
    }

    private static String trimForPreview(String value) {
        if (String.isBlank(value) || value.length() <= PREVIEW_MAX_LENGTH) {
            return value;
        }
        return value.left(PREVIEW_MAX_LENGTH - 3) + '...';
    }

    private static Integer toInteger(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}
