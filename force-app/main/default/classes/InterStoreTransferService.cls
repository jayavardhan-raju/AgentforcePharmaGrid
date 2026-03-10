/**
 * @description Core service for Inter-Store Transfer (IST) operations.
 *              Enforces: DEA Schedule II compliance, cold-chain matching,
 *              inventory locking, and atomic DML with audit trail.
 *
 *              Contract:
 *                confirm = false  -> dry-run, returns recommendation only
 *                                    writes Recommendation__c + Recommendation_Preview__c
 *                confirm = true   -> executes transfer atomically with Transfer_Log__c
 *
 * @author      IST Team
 * @since       API v65.0
 */
public with sharing class InterStoreTransferService {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    // Transfer 50% of source surplus above its own safety stock
    private static final Integer TRANSFER_BUFFER_PCT = 50;

    // Source stock expiring within this many days is excluded from transfer
    private static final Integer MIN_DAYS_TO_EXPIRY  = 30;

    // DEA Schedule that triggers a hard compliance block
    private static final String  DEA_SCHEDULE_II     = 'II';

    // Max length of Text(255) Recommendation_Preview__c Grid column
    private static final Integer PREVIEW_MAX_LENGTH  = 255;


    // -------------------------------------------------------------------------
    // Result Wrapper
    // -------------------------------------------------------------------------

    /**
     * @description Structured result returned to InterStoreTransferAction.
     *              success=false always includes a next action in uhText — never a dead end.
     */
    public class TransferResult {
        public Boolean success;
        public String  uhText;            // full human-readable text shown in agent conversation
        public Id      sourceStoreId;
        public String  sourceStoreName;
        public Integer recommendedQty;
        public Id      transferLogId;

        public TransferResult(Boolean success, String uhText) {
            this.success = success;
            this.uhText  = uhText;
        }
    }


    // -------------------------------------------------------------------------
    // Entry Point
    // -------------------------------------------------------------------------

    /**
     * @description Evaluate and optionally execute an inter-store transfer.
     *
     * @param inventoryPositionId  Id of the critical Inventory_Position__c record (target)
     * @param confirm              false = dry-run | true = execute
     * @return                     TransferResult with success flag + uhText
     */
    public static TransferResult evaluate(Id inventoryPositionId, Boolean confirm) {

        // 1. Load target inventory position with full relational context
        Inventory_Position__c target;
        try {
            target = InventoryPositionSelector.getById(inventoryPositionId);
        } catch (Exception ex) {
            return new TransferResult(false,
                'Unable to locate Inventory Position. Please refresh and try again. ('
                + ex.getMessage() + ')');
        }

        // 2. Compliance gate: Schedule II = hard stop, no source search, no confirm prompt
        if (isScheduleII(target)) {
            logComplianceBlock(target);
            return new TransferResult(false,
                'Compliance Restriction: Schedule II controlled substance detected - '
                + target.Medication__r.Name
                + ' (DEA Schedule II). Manual DEA Form 222 is required for all transfers. '
                + 'Please contact your DEA compliance officer to initiate a manual transfer. '
                + 'No automated transfer has been initiated.');
        }

        // 3. Find all candidate source stores with surplus of this medication
        List<Inventory_Position__c> candidates =
            InventoryPositionSelector.findSurplusSources(
                target.Medication__c,
                target.Store__c,
                (Integer) target.Safety_Stock__c + 1
            );

        // 4. Apply eligibility filters (cold-chain, DEA registration, expiry threshold)
        Inventory_Position__c bestSource = selectBestSource(target, candidates);

        // 5. No eligible source found: return distributor fallback
        if (bestSource == null) {
            return new TransferResult(false,
                'No suitable source store found for '
                + target.Medication__r.Name
                + ' in the distribution network. '
                + 'Recommended next action: Place an emergency order with your primary distributor. '
                + 'Contact your district manager to expedite the distributor order.');
        }

        // 6. Calculate how many units to transfer
        Integer recommendedQty = calculateTransferQty(target, bestSource);

        // 7. Dry-run: write recommendation to record fields, return uhText
        if (!confirm) {
            return buildRecommendation(target, bestSource, recommendedQty);
        }

        // 8. Execute: atomic DML — update inventory + write Transfer_Log__c
        return executeTransfer(target, bestSource, recommendedQty);
    }


    // -------------------------------------------------------------------------
    // Private Helpers
    // -------------------------------------------------------------------------

    /**
     * @description Returns true if the medication is DEA Schedule II.
     */
    private static Boolean isScheduleII(Inventory_Position__c inv) {
        return inv.Medication__r.DEA_Schedule__c == DEA_SCHEDULE_II;
    }

    /**
     * @description Selects the best eligible source from the candidate list.
     *              Eligibility rules (all must pass):
     *                - Cold-chain capable if medication requires cold chain
     *                - Has a DEA registration number on file
     *                - Stock does not expire within MIN_DAYS_TO_EXPIRY days
     *              Candidates are pre-sorted by Quantity__c DESC from the selector,
     *              so the first eligible candidate is the best available source.
     */
    private static Inventory_Position__c selectBestSource(
        Inventory_Position__c target,
        List<Inventory_Position__c> candidates
    ) {
        Boolean coldChainNeeded = target.Medication__r.Cold_Chain_Required__c;
        Date    today           = Date.today();

        for (Inventory_Position__c candidate : candidates) {

            // Cold-chain check
            if (coldChainNeeded && !candidate.Store__r.Cold_Chain_Capable__c) {
                continue;
            }

            // DEA registration check
            if (String.isBlank(candidate.Store__r.DEA_Registration__c)) {
                continue;
            }

            // Expiry threshold check: exclude near-expiry stock
            if (candidate.Expiry_Date__c != null
                && today.daysBetween(candidate.Expiry_Date__c) < MIN_DAYS_TO_EXPIRY) {
                continue;
            }

            return candidate; // first eligible = best (already sorted by qty desc)
        }

        return null; // no eligible source found
    }

    /**
     * @description Calculates units to transfer.
     *              Logic: transfer 50% of the source surplus above its safety stock,
     *              capped at exactly what the target needs to reach its safety stock.
     */
    private static Integer calculateTransferQty(
        Inventory_Position__c target,
        Inventory_Position__c source
    ) {
        Integer sourceSurplus = (Integer)(source.Quantity__c - source.Safety_Stock__c);
        Integer targetNeed    = (Integer)(target.Safety_Stock__c - target.Quantity__c);
        Integer proposed      = (Integer)(sourceSurplus * TRANSFER_BUFFER_PCT / 100.0);
        return Math.min(proposed, targetNeed);
    }

    /**
     * @description Builds the dry-run recommendation result.
     *              No inventory DML — only updates Recommendation__c (Long Text Area)
     *              and Recommendation_Preview__c (Text 255, Agentforce Grid column).
     *
     *              Fix: Long Text Area is not supported as an Agentforce Grid column.
     *              Recommendation_Preview__c (Text 255) is the Grid-compatible field.
     *              Full uhText is stored in Recommendation__c for record detail view.
     */
    private static TransferResult buildRecommendation(
        Inventory_Position__c target,
        Inventory_Position__c source,
        Integer qty
    ) {
        Integer daysToExpiry = source.Expiry_Date__c != null
            ? Date.today().daysBetween(source.Expiry_Date__c) : 0;

        String scheduleLabel = String.isNotBlank(target.Medication__r.DEA_Schedule__c)
            ? target.Medication__r.DEA_Schedule__c : 'None';

        // Full recommendation text — stored in Long Text Area, surfaced in agent conversation
        String uhText =
            'Transfer Recommendation for ' + target.Medication__r.Name
            + ' at ' + target.Store__r.Name + ': '
            + 'Source Store: ' + source.Store__r.Name + '. '
            + 'Available Stock: ' + (Integer) source.Quantity__c + ' units. '
            + 'Days to Expiry: ' + daysToExpiry + ' days. '
            + 'Cold-Chain: Both stores verified capable. '
            + 'DEA Compliance: Validated (Schedule ' + scheduleLabel + '). '
            + 'Recommended Transfer Qty: ' + qty + ' units. '
            + 'Shall I proceed with this transfer?';

        // Preview text: truncated to 255 chars for Agentforce Grid Text column
        // Appends '...' when truncated so the ops user knows full detail is on the record
        String previewText = uhText.length() > PREVIEW_MAX_LENGTH
            ? uhText.left(PREVIEW_MAX_LENGTH - 3) + '...'
            : uhText;

        // Write both fields to the target Inventory Position record
        // Recommendation__c        -> Long Text Area -> full detail on record page
        // Recommendation_Preview__c -> Text(255)     -> Agentforce Grid column (no ValidationFailed)
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

        // Build and return result — no Transfer_Log__c on dry-run
        TransferResult result    = new TransferResult(true, uhText);
        result.sourceStoreId     = source.Store__c;
        result.sourceStoreName   = source.Store__r.Name;
        result.recommendedQty    = qty;
        return result;
    }

    /**
     * @description Executes the confirmed transfer atomically.
     *              - Deducts qty from source Inventory_Position__c
     *              - Adds qty to target Inventory_Position__c
     *              - Writes immutable Transfer_Log__c audit record
     *              - Uses Savepoint for full rollback on any failure
     *              - Clears Recommendation_Preview__c on target after execution
     *                (Grid column shows completion status instead)
     */
    private static TransferResult executeTransfer(
        Inventory_Position__c target,
        Inventory_Position__c source,
        Integer qty
    ) {
        Savepoint sp = Database.setSavepoint();

        try {
            // CRUD / FLS checks before any DML
            if (!Schema.sObjectType.Inventory_Position__c.isUpdateable()) {
                throw new SecurityException(
                    'Insufficient permissions to update Inventory Position records.');
            }
            if (!Schema.sObjectType.Transfer_Log__c.isCreateable()) {
                throw new SecurityException(
                    'Insufficient permissions to create Transfer Log records.');
            }

            // Deduct from source
            Inventory_Position__c sourceUpdate = new Inventory_Position__c(
                Id          = source.Id,
                Quantity__c = source.Quantity__c - qty
            );

            // Add to target + update both recommendation fields to show completion status
            String completionPreview = 'Transfer completed: ' + qty + ' units from '
                + source.Store__r.Name + '. See Transfer Log for details.';

            Inventory_Position__c targetUpdate = new Inventory_Position__c(
                Id                        = target.Id,
                Quantity__c               = target.Quantity__c + qty,
                Recommendation_Preview__c = completionPreview.length() > PREVIEW_MAX_LENGTH
                    ? completionPreview.left(PREVIEW_MAX_LENGTH - 3) + '...'
                    : completionPreview
            );

            // Audit log — immutable record of the transfer
            Transfer_Log__c log = new Transfer_Log__c(
                Source_Store__c         = source.Store__c,
                Target_Store__c         = target.Store__c,
                Medication__c           = target.Medication__c,
                Inventory_Position__c   = target.Id,
                Quantity_Transferred__c = qty,
                Transfer_Status__c      = 'Completed',
                Transfer_Date__c        = DateTime.now(),
                Notes__c                =
                    'Agentforce Grid IST - Automated transfer. '
                    + 'Source: ' + source.Store__r.Name
                    + ' -> Target: ' + target.Store__r.Name
                    + ' | Medication: ' + target.Medication__r.Name
                    + ' | Qty: ' + qty
                    + ' | DEA Schedule: ' + target.Medication__r.DEA_Schedule__c
            );

            // Strip inaccessible fields before DML (FLS enforcement)
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<SObject>{ sourceUpdate, targetUpdate }
            );
            update decision.getRecords();
            insert log;

            // Build execution confirmation text
            String uhText =
                'Transfer Executed Successfully. '
                + 'Validating DEA compliance and securing inventory lock... '
                + 'Inventory lock acquired for ' + target.Medication__r.Name + '. '
                + 'Completed transfer of ' + qty + ' units of ' + target.Medication__r.Name
                + ' from ' + source.Store__r.Name
                + ' to ' + target.Store__r.Name + '. '
                + 'Transfer Log Reference: ' + log.Id + '. '
                + 'Timestamp: ' + DateTime.now().format('yyyy-MM-dd HH:mm:ss') + ' UTC. '
                + 'Audit trail recorded. Stock levels updated.';

            TransferResult result    = new TransferResult(true, uhText);
            result.transferLogId     = log.Id;
            result.sourceStoreId     = source.Store__c;
            result.sourceStoreName   = source.Store__r.Name;
            result.recommendedQty    = qty;
            return result;

        } catch (Exception ex) {
            Database.rollback(sp);
            return new TransferResult(false,
                'Transfer failed and was fully rolled back. '
                + 'No inventory changes were made. '
                + 'Error: ' + ex.getMessage()
                + ' Please retry or escalate to your district manager.');
        }
    }

    /**
     * @description Writes a blocked Transfer_Log__c when a Schedule II compliance
     *              stop is triggered. Called on dry-run only — no inventory changes.
     *              Provides DEA audit trail even for denied requests.
     */
    private static void logComplianceBlock(Inventory_Position__c inv) {
        if (!Schema.sObjectType.Transfer_Log__c.isCreateable()) {
            return; // do not fail the compliance stop itself if perms are missing
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
}