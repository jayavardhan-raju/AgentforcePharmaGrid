/**
 * @description Shared test data factory for all IST test classes.
 */
@IsTest
public class ISTTestDataFactory {

    public static Pharmacy_Store__c createStore(
        String name, Boolean coldChain, String deaReg, Boolean active
    ) {
        Pharmacy_Store__c store = new Pharmacy_Store__c(
            Name                    = name,
            District__c             = 'District 1',
            Latitude__c             = 37.7749,
            Longitude__c            = -122.4194,
            Cold_Chain_Capable__c   = coldChain,
            DEA_Registration__c     = deaReg,
            Is_Active__c            = active
        );
        insert store;
        return store;
    }

    public static Medication__c createMedication(
        String name, String deaSchedule, Boolean coldChain
    ) {
        Medication__c med = new Medication__c(
            Name                    = name,
            NDC__c                  = 'NDC-' + name.replace(' ', '-') + '-001',
            DEA_Schedule__c         = deaSchedule,
            Cold_Chain_Required__c  = coldChain
        );
        insert med;
        return med;
    }

    public static Inventory_Position__c createInventory(
        Id storeId, Id medId, Integer qty, Integer safetyStock, Integer daysToExpiry
    ) {
        Inventory_Position__c inv = new Inventory_Position__c(
            Store__c          = storeId,
            Medication__c     = medId,
            Quantity__c       = qty,
            Safety_Stock__c   = safetyStock,
            Expiry_Date__c    = Date.today().addDays(daysToExpiry),
            Recommendation__c = ''
        );
        insert inv;
        return inv;
    }
}