/**
 * ============================================================================
 * Script 2 of 3: Create Medication Records
 * ============================================================================
 * 
 * Run via: sf apex run --file scripts/apex/2_Create_Medications.apex --target-org <alias>
 * 
 * Creates 6 medications with varied regulatory and handling attributes:
 *   - Schedule II controlled substances (will trigger compliance hard stop)
 *   - Cold-chain required medications (filters source stores by capability)
 *   - Standard non-controlled medications (happy path)
 *   - Various DEA schedules (III, IV, V, None)
 * 
 * IMPORTANT: Run Script 1 (Pharmacy Stores) before this script.
 *            Run Script 3 (Inventory Positions) after this script.
 * ============================================================================
 */

List<Medication__c> meds = new List<Medication__c>{

    // ── Cold-Chain + Non-Controlled ───────────────────────────────────────
    new Medication__c(
        Name                    = 'Mounjaro 5mg',
        NDC__c                  = '00002-1523-80',
        DEA_Schedule__c         = 'None',
        Cold_Chain_Required__c  = true           // Requires cold chain — filters non-capable stores
    ),
    new Medication__c(
        Name                    = 'Ozempic 1mg',
        NDC__c                  = '00169-4132-12',
        DEA_Schedule__c         = 'None',
        Cold_Chain_Required__c  = true           // Requires cold chain
    ),

    // ── Schedule II Controlled Substance (Hard Compliance Block) ──────────
    new Medication__c(
        Name                    = 'Adderall XR 30mg',
        NDC__c                  = '54092-0391-01',
        DEA_Schedule__c         = 'II',          // Schedule II = automatic transfer block
        Cold_Chain_Required__c  = false
    ),

    // ── Schedule IV Controlled (Allowed for automated transfer) ───────────
    new Medication__c(
        Name                    = 'Xanax 0.5mg',
        NDC__c                  = '00009-0055-01',
        DEA_Schedule__c         = 'IV',
        Cold_Chain_Required__c  = false
    ),

    // ── Standard Non-Controlled ──────────────────────────────────────────
    new Medication__c(
        Name                    = 'Lisinopril 10mg',
        NDC__c                  = '00093-1044-01',
        DEA_Schedule__c         = 'None',
        Cold_Chain_Required__c  = false
    ),
    new Medication__c(
        Name                    = 'Amoxicillin 500mg',
        NDC__c                  = '65862-0015-01',
        DEA_Schedule__c         = 'None',
        Cold_Chain_Required__c  = false
    )
};

insert meds;

System.debug('========================================');
System.debug('Created ' + meds.size() + ' Medication records:');
for (Medication__c m : meds) {
    System.debug('  [' + m.Id + '] ' + m.Name
        + ' | NDC: ' + m.NDC__c
        + ' | DEA: ' + m.DEA_Schedule__c
        + ' | Cold Chain: ' + m.Cold_Chain_Required__c);
}
System.debug('========================================');
