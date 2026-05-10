/**
 * @description Agentforce Invocable Action: Execute Inter-Store Transfer
 *
 *              Supports dry-run (confirm=false) and execution (confirm=true).
 *              The Grid's Transfer/Optimize button triggers this action.
 *              The agent calls it twice per workflow:
 *                1st call: confirm=false  → recommendation + "Shall I proceed?"
 *                2nd call: confirm=true   → atomic execution
 *
 * @author      IST Team
 * @since       API v65.0
 */
public with sharing class InterStoreTransferAction {

    /**
     * Input wrapper — Agentforce passes these from the Grid row context.
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
     * Output wrapper — returned to the Agentforce agent.
     */
    public class ActionOutput {
        @InvocableVariable(
            label       = 'Success'
            description = 'True if recommendation or execution succeeded; false on compliance/fallback blocks.'
        )
        public Boolean success;

        @InvocableVariable(
            label       = 'UH Text'
            description = 'Human-readable message for the agent to surface in the Grid conversation.'
        )
        public String uhText;

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
            label       = 'Transfer Log ID'
            description = 'ID of the Transfer_Log__c record created on execution (null on dry-run).'
        )
        public Id transferLogId;
    }

    /**
     * Invocable entry point called by Agentforce.
     * Accepts a list (Agentforce always passes a list of 1 for single-row actions).
     */
    @InvocableMethod(
        label       = 'Execute Inter-Store Transfer'
        description = 'Recommends (dry-run) or executes an inter-store inventory transfer for a critical stock row. Schedule II drugs are automatically blocked. Returns uhText for agent to surface.'
        category    = 'Inventory Management'
        callout     = false
    )
    public static List<ActionOutput> execute(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            Boolean confirmFlag = input.confirm != null ? input.confirm : false;
            System.debug('======>input.confirm='+input.confirm);
            System.debug('======>input.inventoryPositionId='+input.inventoryPositionId);
            InterStoreTransferService.TransferResult result =
                InterStoreTransferService.evaluate(input.inventoryPositionId, confirmFlag);
                        System.debug('======>result='+result);

            ActionOutput out = new ActionOutput();
            out.success        = result.success;
            out.uhText         = result.uhText;
            out.sourceStoreId  = result.sourceStoreId;
            out.sourceStoreName = result.sourceStoreName;
            out.recommendedQty = result.recommendedQty;
            out.transferLogId  = result.transferLogId;
            outputs.add(out);
        }

        return outputs;
    }
}