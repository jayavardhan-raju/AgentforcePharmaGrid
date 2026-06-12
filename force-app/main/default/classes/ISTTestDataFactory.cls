/**
 * @description Shared test data factory for all IST test classes.
 */
@IsTest
public class ISTTestDataFactory {

    private static final String OPS_USER_USERNAME_PREFIX = 'ist.ops.user.';

    /**
     * @description Creates a test user and assigns the IST_Ops_User permission set
     *              so test methods can run as a non-admin user without access errors.
     *              Setup-object DML (User, PermissionSetAssignment) is wrapped in
     *              System.runAs to avoid MIXED_DML_OPERATION with the non-setup
     *              test data created in @TestSetup.
     */
    public static User createOpsUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueSuffix = String.valueOf(Datetime.now().getTime())
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User opsUser = new User(
            FirstName         = 'IST',
            LastName          = 'OpsUser',
            Alias             = 'istops',
            Email             = 'ist.ops.user@pharmagrid.example.com',
            Username          = OPS_USER_USERNAME_PREFIX + uniqueSuffix + '@pharmagrid.example.com',
            ProfileId         = standardProfile.Id,
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles'
        );

        PermissionSet istOpsPermSet = [
            SELECT Id FROM PermissionSet WHERE Name = 'IST_Ops_User' LIMIT 1
        ];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert opsUser;
            insert new PermissionSetAssignment(
                AssigneeId      = opsUser.Id,
                PermissionSetId = istOpsPermSet.Id
            );
        }
        return opsUser;
    }

    /**
     * @description Returns the ops test user created in @TestSetup via createOpsUser().
     */
    public static User getOpsUser() {
        return [
            SELECT Id, Username
            FROM User
            WHERE Username LIKE :(OPS_USER_USERNAME_PREFIX + '%')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

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
