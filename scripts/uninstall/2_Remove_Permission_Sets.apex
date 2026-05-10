/**
 * ============================================================================
 * Uninstall Script 2 of 2: Remove Permission Set Assignments
 * ============================================================================
 * 
 * Run via: sf apex run --file scripts/uninstall/2_Remove_Permission_Sets.apex --target-org <alias>
 * 
 * Removes IST_Ops_User permission set assignments from all users.
 * This must be done BEFORE deploying destructiveChanges.xml because
 * permission sets cannot be deleted while they have active assignments.
 * 
 * IMPORTANT: Run this AFTER deleting sample data (Script 1)
 *            and BEFORE deploying destructiveChanges.xml
 * ============================================================================
 */

System.debug('========================================');
System.debug('Starting Permission Set Removal');
System.debug('========================================');

try {
    // Query the IST_Ops_User permission set
    List<PermissionSet> permissionSets = [
        SELECT Id, Name 
        FROM PermissionSet 
        WHERE Name = 'IST_Ops_User' 
        LIMIT 1
    ];
    
    if (permissionSets.isEmpty()) {
        System.debug('IST_Ops_User permission set not found. May already be deleted.');
    } else {
        PermissionSet ps = permissionSets[0];
        System.debug('Found permission set: ' + ps.Name + ' (ID: ' + ps.Id + ')');
        
        // Query all assignments for this permission set
        List<PermissionSetAssignment> assignments = [
            SELECT Id, AssigneeId, Assignee.Name, Assignee.Username
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :ps.Id
        ];
        
        if (assignments.isEmpty()) {
            System.debug('No permission set assignments found.');
        } else {
            System.debug('Found ' + assignments.size() + ' permission set assignment(s):');
            
            // Log each assignment before deletion
            for (PermissionSetAssignment psa : assignments) {
                System.debug('  - User: ' + psa.Assignee.Name + ' (' + psa.Assignee.Username + ')');
            }
            
            // Delete all assignments
            delete assignments;
            System.debug('');
            System.debug('Successfully removed ' + assignments.size() + ' permission set assignment(s)');
        }
    }
    
    System.debug('========================================');
    System.debug('Permission Set Removal Complete');
    System.debug('========================================');
    System.debug('Next Step: Deploy destructiveChanges.xml to remove all metadata');
    System.debug('Command: sf project deploy start --manifest manifest/destructiveChanges.xml --post-destructive-changes manifest/destructivePackage.xml --target-org <alias>');
    
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, 'Error removing permission sets: ' + e.getMessage());
    System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
    throw e;
}