#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Migrates Azure RBAC role assignments from one Management Group to another.

.DESCRIPTION
    Reads all role assignments scoped directly to a source Management Group,
    exports them to CSV, and reapplies them to a target Management Group.
    The script is idempotent -- it skips assignments that already exist at the
    target and logs every action taken.

.PARAMETER SourceMG
    Name (not display name) of the source Management Group.

.PARAMETER TargetMG
    Name (not display name) of the target Management Group.

.PARAMETER ExportPath
    Path for the CSV export file.  Defaults to ./rbac-export-<SourceMG>.csv

.PARAMETER WhatIf
    When set, the script logs what it WOULD do without making changes.

.PARAMETER SkipExport
    When set, skips the export step (useful on a re-run where the CSV already
    exists and you only want to apply).

.EXAMPLE
    # Dry run
    .\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW" -WhatIf

    # Execute
    .\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW"

    # Re-run apply only (CSV already exported)
    .\Migrate-RbacAssignments.ps1 -SourceMG "MG-OLD" -TargetMG "MG-NEW" -SkipExport
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SourceMG,

    [Parameter(Mandatory)]
    [string]$TargetMG,

    [string]$ExportPath,

    [switch]$SkipExport
)

# ============================================================================
# Setup
# ============================================================================
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $ExportPath) {
    $ExportPath = Join-Path $PSScriptRoot "rbac-export-$SourceMG.csv"
}

$logFile = Join-Path $PSScriptRoot "rbac-migration-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# ============================================================================
# Pre-flight checks
# ============================================================================
Write-Log "RBAC Migration: $SourceMG --> $TargetMG"
Write-Log "Export CSV : $ExportPath"
Write-Log "Log file   : $logFile"

# Verify Azure context
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Log 'No Azure context found. Run Connect-AzAccount first.' 'ERROR'
    exit 1
}
Write-Log "Signed in as: $($ctx.Account.Id) | Tenant: $($ctx.Tenant.Id)"

# Build scope strings
$sourceMGScope = "/providers/Microsoft.Management/managementGroups/$SourceMG"
$targetMGScope = "/providers/Microsoft.Management/managementGroups/$TargetMG"

# Validate both Management Groups exist
try {
    $null = Get-AzManagementGroup -GroupId $SourceMG
    Write-Log "Source MG '$SourceMG' exists."
} catch {
    Write-Log "Source MG '$SourceMG' not found or no access: $_" 'ERROR'
    exit 1
}

try {
    $null = Get-AzManagementGroup -GroupId $TargetMG
    Write-Log "Target MG '$TargetMG' exists."
} catch {
    Write-Log "Target MG '$TargetMG' not found or no access: $_" 'ERROR'
    exit 1
}

# ============================================================================
# Phase 1 -- Discover & Export
# ============================================================================
if (-not $SkipExport) {
    Write-Log '--- Phase 1: Discover & Export ---'

    # Get assignments scoped directly to the source MG (not inherited)
    $allAssignments = @(Get-AzRoleAssignment -Scope $sourceMGScope |
        Where-Object { $_.Scope -eq $sourceMGScope })

    Write-Log "Found $($allAssignments.Count) direct role assignment(s) at $SourceMG."

    if ($allAssignments.Count -eq 0) {
        Write-Log 'Nothing to migrate.' 'WARN'
        exit 0
    }

    # Build export objects
    $exportData = @($allAssignments | ForEach-Object {
        [PSCustomObject]@{
            RoleAssignmentId   = $_.RoleAssignmentId
            RoleDefinitionName = $_.RoleDefinitionName
            RoleDefinitionId   = $_.RoleDefinitionId
            ObjectId           = $_.ObjectId
            ObjectType         = $_.ObjectType
            DisplayName        = $_.DisplayName
            SignInName         = $_.SignInName
            Scope              = $_.Scope
            Description        = $_.Description
            Condition          = $_.Condition
            ConditionVersion   = $_.ConditionVersion
        }
    })

    $exportData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "Exported $($exportData.Count) assignment(s) to $ExportPath"
} else {
    Write-Log '--- Phase 1: Skipped (SkipExport flag) ---'
    if (-not (Test-Path $ExportPath)) {
        Write-Log "Export file not found at $ExportPath. Cannot proceed." 'ERROR'
        exit 1
    }
}

# ============================================================================
# Phase 2 -- Read CSV & Reapply to Target MG
# ============================================================================
Write-Log '--- Phase 2: Reapply assignments to Target MG ---'

$csv = @(Import-Csv -Path $ExportPath)
Write-Log "Loaded $($csv.Count) assignment(s) from CSV."

# Pre-fetch existing assignments at target to detect duplicates
$existingAtTarget = @(Get-AzRoleAssignment -Scope $targetMGScope |
    Where-Object { $_.Scope -eq $targetMGScope })

Write-Log "Target MG already has $($existingAtTarget.Count) direct assignment(s)."

$created  = 0
$skipped  = 0
$failed   = 0

foreach ($row in $csv) {
    $label = "'$($row.RoleDefinitionName)' for $($row.DisplayName) ($($row.ObjectType))"

    # Idempotency check -- does this exact assignment already exist at the target?
    $duplicate = $existingAtTarget | Where-Object {
        $_.ObjectId -eq $row.ObjectId -and
        $_.RoleDefinitionId -eq $row.RoleDefinitionId
    }

    if ($duplicate) {
        Write-Log "SKIP (already exists): $label"
        $skipped++
        continue
    }

    # Build splat for New-AzRoleAssignment
    $params = @{
        ObjectId           = $row.ObjectId
        RoleDefinitionName = $row.RoleDefinitionName
        Scope              = $targetMGScope
    }

    # If the role definition name lookup might fail (custom role not available
    # at target scope), fall back to RoleDefinitionId
    $useRoleId = $false

    # Check if it is a custom role by testing if RoleDefinitionId contains
    # a non-standard GUID path (custom roles have the MG/sub scope in the ID)
    if ($row.RoleDefinitionId -notmatch '^/providers/Microsoft\.Authorization/roleDefinitions/') {
        $useRoleId = $true
    }

    # Add optional condition (for ABAC / conditions)
    if ($row.Condition -and $row.Condition -ne '') {
        $params['Condition']        = $row.Condition
        $params['ConditionVersion'] = if ($row.ConditionVersion) { $row.ConditionVersion } else { '2.0' }
    }

    # Add description if present
    if ($row.Description -and $row.Description -ne '') {
        $params['Description'] = $row.Description
    }

    if ($PSCmdlet.ShouldProcess($label, 'New-AzRoleAssignment')) {
        try {
            if ($useRoleId) {
                $params.Remove('RoleDefinitionName')
                $params['RoleDefinitionId'] = $row.RoleDefinitionId
                Write-Log "Using RoleDefinitionId for custom role: $label"
            }
            $null = New-AzRoleAssignment @params
            Write-Log "CREATED: $label"
            $created++
        } catch {
            $errMsg = $_.Exception.Message
            # Handle the 'role assignment already exists' race condition
            if ($errMsg -match 'role assignment already exists') {
                Write-Log "SKIP (race condition duplicate): $label" 'WARN'
                $skipped++
            } elseif ($errMsg -match 'does not exist in the directory') {
                Write-Log "SKIP (principal not found in directory): $label" 'WARN'
                $skipped++
            } elseif ($errMsg -match 'AuthorizationFailed|does not have authorization') {
                Write-Log "FAIL (insufficient permissions): $label" 'ERROR'
                $failed++
            } else {
                Write-Log "FAIL: $label -- $errMsg" 'ERROR'
                $failed++
            }
        }
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Log '--- Migration Summary ---'
Write-Log "Total in CSV : $($csv.Count)"
Write-Log "Created      : $created"
Write-Log "Skipped      : $skipped"
Write-Log "Failed       : $failed"

if ($failed -gt 0) {
    Write-Log 'Some assignments failed. Review the log and re-run after fixing permissions.' 'WARN'
    exit 2
}

Write-Log 'Migration completed successfully.'
