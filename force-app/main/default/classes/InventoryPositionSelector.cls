/**
 * @description Selector for Inventory_Position__c — ALL SOQL for inventory queries.
 *              No DML. No business logic. Only reads.
 * @author      IST Team
 * @since       API v65.0
 */
public with sharing class InventoryPositionSelector {

    /**
     * Fetch a single inventory position with full context for transfer evaluation.
     */
    public static Inventory_Position__c getById(Id inventoryPositionId) {
        if (inventoryPositionId == null) {
            throw new IllegalArgumentException('inventoryPositionId cannot be null');
        }

        List<Inventory_Position__c> results = [
            SELECT Id,
                   Name,
                   Store__c,
                   Store__r.Name,
                   Store__r.Latitude__c,
                   Store__r.Longitude__c,
                   Store__r.Cold_Chain_Capable__c,
                   Store__r.DEA_Registration__c,
                   Store__r.Is_Active__c,
                   Medication__c,
                   Medication__r.Name,
                   Medication__r.DEA_Schedule__c,
                   Medication__r.Cold_Chain_Required__c,
                   Quantity__c,
                   Safety_Stock__c,
                   Expiry_Date__c,
                   Status__c,
                   Recommendation__c
            FROM   Inventory_Position__c
            WHERE  Id = :inventoryPositionId
            WITH   USER_MODE
            LIMIT  1
        ];

        if (results.isEmpty()) {
            throw new QueryException('Inventory Position not found: ' + inventoryPositionId);
        }
        return results[0];
    }

    /**
     * Find candidate source stores that hold surplus of a given medication.
     * Excludes the target store. Orders by quantity descending (most surplus first).
     */
    public static List<Inventory_Position__c> findSurplusSources(
        Id medicationId,
        Id excludeStoreId,
        Integer minimumSurplus
    ) {
        Integer minQty = minimumSurplus == null ? 1 : minimumSurplus;

        return [
            SELECT Id,
                   Name,
                   Store__c,
                   Store__r.Name,
                   Store__r.Latitude__c,
                   Store__r.Longitude__c,
                   Store__r.Cold_Chain_Capable__c,
                   Store__r.DEA_Registration__c,
                   Store__r.Is_Active__c,
                   Medication__c,
                   Medication__r.Name,
                   Medication__r.DEA_Schedule__c,
                   Medication__r.Cold_Chain_Required__c,
                   Quantity__c,
                   Safety_Stock__c,
                   Expiry_Date__c,
                   Status__c
            FROM   Inventory_Position__c
            WHERE  Medication__c = :medicationId
            AND    Store__c      != :excludeStoreId
            AND    Quantity__c   >  :minQty
            AND    Store__r.Is_Active__c = true
            WITH  USER_MODE
            ORDER BY Quantity__c DESC
        ];
    }
}