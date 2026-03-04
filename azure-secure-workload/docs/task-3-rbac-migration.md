# Task 3 RBAC Migration Automation

## Scenario

The organization is restructuring Management Groups. All existing RBAC role assignments need to move from MG-OLD to MG-NEW. The migration must handle users, groups, service principals, built-in roles, and custom roles. There is no access to the Root Management Group.

## Task 3.1 -- Automation Strategy

### Phase 1: Discover

Connect to Azure with a principal that has `Microsoft.Authorization/roleAssignments/read` at both MG-OLD and MG-NEW scope. Run `Get-AzRoleAssignment -Scope <MG-OLD>` to list all assignments.

Filter to direct assignments only. Inherited assignments (where the scope does not match the MG-OLD path) belong to a parent and should not be duplicated.

For each assignment, capture the role definition name, role definition ID, principal object ID, object type, display name, sign-in name, conditions (for ABAC), and description.

### Phase 2: Export

Write everything to a CSV file. This file serves two purposes: it is the input for the migration script, and it is the audit trail of what was in place before the migration started.

### Phase 3: Pre-flight Validation

Before creating anything at MG-NEW, validate that every principal in the CSV still exists in Entra ID. Deleted users or deprovisioned service principals will cause assignment failures. Flag these as orphans and skip them.

For custom roles, verify that their `AssignableScopes` includes MG-NEW. If a custom role is only scoped to MG-OLD, it will not be assignable at MG-NEW until the role definition is updated.

### Phase 4: Reapply

Read the CSV. For each row, check if the same assignment already exists at MG-NEW (same ObjectId + same RoleDefinitionId). If it does, skip it. If it doesn't, create it with `New-AzRoleAssignment`.

Built-in roles are assigned by name. Custom roles fall back to RoleDefinitionId since the name might not resolve at the new scope.

Log every action: created, skipped, or failed.

### Phase 5: Validate

Re-enumerate assignments at MG-NEW and compare against the CSV. Every row in the CSV should have a matching assignment at MG-NEW. If any are missing, re-run the script (it is idempotent) or investigate the logged errors.

### Phase 6: Cleanup

Once MG-NEW is confirmed correct, either remove the old assignments from MG-OLD or leave them if MG-OLD will be deleted entirely.

## Task 3.2 -- PowerShell Script

The script is at `scripts/Migrate-RbacAssignments.ps1`.

### What it does

- Validates Azure context and confirms both Management Groups exist
- Reads all direct role assignments from the source MG
- Exports them to CSV (with all fields needed for recreation)
- Pre-fetches existing assignments at the target MG for duplicate detection
- Creates missing assignments at the target, skipping duplicates
- Handles errors gracefully: catches authorization failures, missing principals, and race-condition duplicates
- Supports `-WhatIf` for dry runs
- Supports `-SkipExport` to reuse an existing CSV on re-runs
- Writes a timestamped log file
- Exits with code 2 if any assignments failed, so CI pipelines can detect it

### How to run it

```powershell
# Dry run (shows what would happen, no changes)
.\scripts\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW" -WhatIf

# Full migration
.\scripts\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW"

# Re-run (skip export, reuse existing CSV)
.\scripts\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW" -SkipExport
```

## Task 3.3 -- Risk and Validation

### How to validate a successful migration

Run a count check: the number of direct assignments at MG-NEW should match the number of rows in the CSV (minus any known orphans).

Run an identity check: for every row in the CSV, confirm a matching ObjectId + RoleDefinitionId assignment exists at MG-NEW.

Run a functional test: pick a user or group from the migrated assignments and have them attempt an action at MG-NEW scope that requires the assigned role. If it works, the assignment is functional.

Check the Azure Activity Log for `Microsoft.Authorization/roleAssignments/write` events during the migration window. All entries should correspond to expected assignments.

### Risks involved in MG-level RBAC migration

**Custom role not assignable at MG-NEW.** If the role definition's AssignableScopes does not include MG-NEW, the assignment will fail. Mitigation: check AssignableScopes during pre-flight and update the role definition first.

**Orphaned principals.** If a user or service principal has been deleted from Entra ID, the assignment fails with "does not exist in directory." The script logs and skips these.

**Insufficient permissions at MG-NEW.** The migration principal needs User Access Administrator or Owner at the target scope. Without it, every assignment fails with AuthorizationFailed.

**Duplicate assignments.** If an assignment already exists, ARM returns a conflict error. The script pre-checks for duplicates and catches the error if a race condition occurs.

**ABAC conditions lost.** If conditions and condition versions are not preserved, condition-based access breaks. The script stores and reapplies both fields.

**Inherited vs direct confusion.** If inherited assignments are not filtered out, they get duplicated at the target scope, creating unintended direct assignments. The script filters by scope.

**Propagation delay.** ARM replication can take 5 to 10 minutes. An assignment might exist but not show up in queries immediately. Wait and re-validate.

### Rollback strategy

The script is additive. It only creates assignments at MG-NEW and never touches MG-OLD. If the migration needs to be reversed:

1. Use the log file to identify what was created during the migration
2. Remove those assignments from MG-NEW with `Remove-AzRoleAssignment`
3. Confirm MG-OLD assignments are still intact (they were never modified)
4. Fix the root cause and re-run the script. Idempotency ensures previously created assignments are skipped.
