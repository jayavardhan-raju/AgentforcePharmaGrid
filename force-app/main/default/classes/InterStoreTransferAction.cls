/**
 * @description Agentforce Invocable Action: Execute Inter-Store Transfer
 *
 *              Supports dry-run (confirm=false) and execution (confirm=true).
 *              The Grid's Transfer/Optimize button triggers this action.
 *
 *              Important Agentforce Grid behavior:
 *              The original Salesforce.Quantity__c column is an imported row value.
 *              Do not rely on that original column to refresh in-place after DML.
 *              This action returns currentQuantity / updatedTargetQuantity so the
 *              Grid can display the post-transfer quantity from the action output.
 *
 * @author      IST Team
 * @since       API v65.0
 */
public with sharing class InterStoreTransferAction {

    /**
     * Input wrapper. Agentforce passes these values from the Grid row context.
     */
    public class ActionInput {
        @InvocableVariable(
            label       = 'Inventory Position ID'
            description = 'The Salesforce ID of the critical Inventory_Position__c record.'
            required    = true
        )
        public Id inventoryPositionId;

        @InvocableVariable(
            label       = 'Confirm Transfer'
            description = 'false = dry-run recommendation only. true = execute the transfer.'
            required    = false
            defaultValue = 'true'
        )
        public Boolean confirm;
    }

    /**
     * Output wrapper returned to Agentforce.
     *
     * Add currentQuantity or updatedTargetQuantity as a Grid column after the
     * action runs. That output is the reliable refreshed value.
     */
    public class ActionOutput {
        @InvocableVariable(
            label       = 'Success'
            description = 'True if recommendation or execution succeeded; false on compliance/fallback blocks.'
        )
        public Boolean success;

        @InvocableVariable(
            label       = 'Transfer Status'
            description = 'Recommended, Executed, Healthy, Blocked, Failed, or Error.'
        )
        public String transferStatus;

        @InvocableVariable(
            label       = 'UH Text'
            description = 'Human-readable message for the agent to surface in the Grid conversation.'
        )
        public String uhText;

        @InvocableVariable(
            label       = 'Target Inventory Position ID'
            description = 'Salesforce ID of the target Inventory_Position__c row.'
        )
        public Id targetInventoryPositionId;

        @InvocableVariable(
            label       = 'Source Inventory Position ID'
            description = 'Salesforce ID of the source Inventory_Position__c row.'
        )
        public Id sourceInventoryPositionId;

        @InvocableVariable(
            label       = 'Source Store ID'
            description = 'Salesforce ID of the recommended source store.'
        )
        public Id sourceStoreId;

        @InvocableVariable(
            label       = 'Source Store Name'
            description = 'Name of the recommended source store.'
        )
        public String sourceStoreName;

        @InvocableVariable(
            label       = 'Recommended Quantity'
            description = 'Number of units recommended for transfer.'
        )
        public Integer recommendedQty;

        @InvocableVariable(
            label       = 'Transferred Quantity'
            description = 'Number of units actually transferred on execution.'
        )
        public Integer transferredQty;

        @InvocableVariable(
            label       = 'Transfer Log ID'
            description = 'ID of the Transfer_Log__c record created on execution.'
        )
        public Id transferLogId;

        @InvocableVariable(
            label       = 'Original Target Quantity'
            description = 'Target Inventory_Position__c quantity before action execution.'
        )
        public Decimal originalTargetQuantity;

        @InvocableVariable(
            label       = 'Updated Target Quantity'
            description = 'Target Inventory_Position__c quantity after action execution or current value if no transfer occurred.'
        )
        public Decimal updatedTargetQuantity;

        @InvocableVariable(
            label       = 'Current Quantity'
            description = 'Recommended Grid display value for the target row after the action.'
        )
        public Decimal currentQuantity;

        @InvocableVariable(
            label       = 'Original Source Quantity'
            description = 'Source Inventory_Position__c quantity before action execution.'
        )
        public Decimal originalSourceQuantity;

        @InvocableVariable(
            label       = 'Updated Source Quantity'
            description = 'Source Inventory_Position__c quantity after action execution or current value if no transfer occurred.'
        )
        public Decimal updatedSourceQuantity;
    }

    /**
     * Invocable entry point called by Agentforce.
     */
    @InvocableMethod(
        label       = 'Execute Inter-Store Transfer'
        description = 'Recommends or executes an inter-store inventory transfer and returns refreshed quantity outputs for Agentforce Grid.'
        category    = 'Inventory Management'
        callout     = false
    )
    public static List<ActionOutput> execute(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }

        for (ActionInput input : inputs) {
            ActionOutput out = new ActionOutput();

            try {
                if (input == null || input.inventoryPositionId == null) {
                    out.success = false;
                    out.transferStatus = 'Error';
                    out.uhText = 'Inventory Position ID is required. Please refresh the Grid row and try again.';
                    outputs.add(out);
                    continue;
                }

                Boolean confirmFlag = input.confirm != null ? input.confirm : false;

                InterStoreTransferService.TransferResult result =
                    InterStoreTransferService.evaluate(input.inventoryPositionId, confirmFlag);

                out.success                   = result.success;
                out.transferStatus            = result.transferStatus;
                out.uhText                    = result.uhText;
                out.targetInventoryPositionId = result.targetInventoryPositionId;
                out.sourceInventoryPositionId = result.sourceInventoryPositionId;
                out.sourceStoreId             = result.sourceStoreId;
                out.sourceStoreName           = result.sourceStoreName;
                out.recommendedQty            = result.recommendedQty;
                out.transferredQty            = result.transferredQty;
                out.transferLogId             = result.transferLogId;
                out.originalTargetQuantity    = result.originalTargetQuantity;
                out.updatedTargetQuantity     = result.updatedTargetQuantity;
                out.currentQuantity           = result.currentQuantity;
                out.originalSourceQuantity    = result.originalSourceQuantity;
                out.updatedSourceQuantity     = result.updatedSourceQuantity;

            } catch (Exception ex) {
                out.success = false;
                out.transferStatus = 'Error';
                out.uhText =
                    'Transfer action failed before completion. No Grid refresh value was produced. '
                    + 'Error: ' + ex.getMessage();
            }

            outputs.add(out);
        }

        return outputs;
    }
}
