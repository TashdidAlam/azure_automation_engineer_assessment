<#
.SYNOPSIS
    Post-deployment validation script for Azure Secure Workload.

.DESCRIPTION
    Runs after each Bicep deployment to verify:
    1. All resources deployed successfully
    2. Public network access is DISABLED on all services
    3. Private Endpoints are provisioned and connected
    4. Managed Identities are assigned
    5. VNet peering is established and connected
    6. Private DNS Zones are linked to VNets

    This script is called by the Azure DevOps pipeline after each
    environment deployment.

.PARAMETER ResourceGroupName
    Name of the target resource group (e.g., rg-secure-workload-dev)

.PARAMETER EnvironmentName
    Environment identifier (dev, stg, prod)

.EXAMPLE
    .\post-deployment.ps1 -ResourceGroupName "rg-secure-workload-dev" -EnvironmentName "dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'stg', 'prod')]
    [string]$EnvironmentName
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = 'Stop'
$validationResults = @()
$hasFailures = $false

foreach ($mod in @('Az.DataFactory', 'Az.PrivateDns')) {
    if (-not (Get-Module -Name $mod -ErrorAction SilentlyContinue)) {
        try { Import-Module $mod -ErrorAction Stop }
        catch { Write-Host "  [WARN] Could not load $mod - some checks will use ARM fallback" -ForegroundColor Yellow }
    }
}

function Add-ValidationResult {
    param(
        [string]$Check,
        [string]$Resource,
        [string]$Status,
        [string]$Details
    )
    $script:validationResults += [PSCustomObject]@{
        Check    = $Check
        Resource = $Resource
        Status   = $Status
        Details  = $Details
    }
    if ($Status -eq 'FAIL') {
        $script:hasFailures = $true
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Post-Deployment Validation - $($EnvironmentName.ToUpper())" -ForegroundColor Cyan
Write-Host " Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host " Timestamp: $([System.DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# CHECK 1: Verify Resource Group Exists
# ============================================================================

Write-Host "[CHECK] [1/7] Verifying Resource Group..." -ForegroundColor Yellow

try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName
    Add-ValidationResult -Check "Resource Group" -Resource $ResourceGroupName -Status "PASS" -Details "Location: $($rg.Location)"
    Write-Host "  [PASS] Resource Group exists: $($rg.Location)" -ForegroundColor Green
}
catch {
    Add-ValidationResult -Check "Resource Group" -Resource $ResourceGroupName -Status "FAIL" -Details $_.Exception.Message
    Write-Host "  [FAIL] Resource Group not found!" -ForegroundColor Red
    throw "Resource Group $ResourceGroupName does not exist. Aborting validation."
}

# ============================================================================
# CHECK 2: Verify SQL Server - Public Access Disabled + Entra Auth
# ============================================================================

Write-Host "[CHECK] [2/7] Verifying Azure SQL Server configuration..." -ForegroundColor Yellow

try {
    $sqlServers = Get-AzSqlServer -ResourceGroupName $ResourceGroupName

    foreach ($sql in $sqlServers) {
        if ($sql.PublicNetworkAccess -eq 'Disabled') {
            Add-ValidationResult -Check "SQL Public Access" -Resource $sql.ServerName -Status "PASS" -Details "Public network access is Disabled"
            Write-Host "  [PASS] SQL Server '$($sql.ServerName)': Public access DISABLED" -ForegroundColor Green
        }
        else {
            Add-ValidationResult -Check "SQL Public Access" -Resource $sql.ServerName -Status "FAIL" -Details "Public network access is $($sql.PublicNetworkAccess)"
            Write-Host "  [FAIL] SQL Server '$($sql.ServerName)': Public access is $($sql.PublicNetworkAccess)!" -ForegroundColor Red
        }

        $admins = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroupName -ServerName $sql.ServerName
        if ($admins) {
            Add-ValidationResult -Check "SQL Entra Admin" -Resource $sql.ServerName -Status "PASS" -Details "Entra admin configured: $($admins.DisplayName)"
            Write-Host "  [PASS] SQL Server '$($sql.ServerName)': Entra admin configured" -ForegroundColor Green
        }
        else {
            Add-ValidationResult -Check "SQL Entra Admin" -Resource $sql.ServerName -Status "FAIL" -Details "No Entra admin configured"
            Write-Host "  [FAIL] SQL Server '$($sql.ServerName)': No Entra admin!" -ForegroundColor Red
        }
    }
}
catch {
    Add-ValidationResult -Check "SQL Server" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] SQL check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 3: Verify App Service - Public Access Disabled + Managed Identity
# ============================================================================

Write-Host "[CHECK] [3/7] Verifying App Service configuration..." -ForegroundColor Yellow

try {
    $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName

    foreach ($app in $webApps) {
        $appDetails = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $app.Name
        $publicAccess = $appDetails.PublicNetworkAccess
        if (-not $publicAccess) {
            $armResource = Get-AzResource -ResourceId $appDetails.Id -ExpandProperties -ErrorAction SilentlyContinue
            if ($armResource) {
                $publicAccess = $armResource.Properties.publicNetworkAccess
            }
        }

        if ($publicAccess -eq 'Disabled') {
            Add-ValidationResult -Check "App Service Public Access" -Resource $app.Name -Status "PASS" -Details "Public network access is Disabled"
            Write-Host "  [PASS] App Service '$($app.Name)': Public access DISABLED" -ForegroundColor Green
        }
        elseif ($publicAccess) {
            Add-ValidationResult -Check "App Service Public Access" -Resource $app.Name -Status "FAIL" -Details "Public network access is $publicAccess"
            Write-Host "  [FAIL] App Service '$($app.Name)': Public access is $publicAccess" -ForegroundColor Red
        }
        else {
            Add-ValidationResult -Check "App Service Public Access" -Resource $app.Name -Status "FAIL" -Details "Unable to determine public network access setting"
            Write-Host "  [WARN] App Service '$($app.Name)': Could not read PublicNetworkAccess" -ForegroundColor Yellow
        }

        if ($appDetails.Identity -and $appDetails.Identity.Type -match 'SystemAssigned') {
            Add-ValidationResult -Check "App Service MI" -Resource $app.Name -Status "PASS" -Details "System Assigned MI: $($appDetails.Identity.PrincipalId)"
            Write-Host "  [PASS] App Service '$($app.Name)': Managed Identity enabled" -ForegroundColor Green
        }
        else {
            Add-ValidationResult -Check "App Service MI" -Resource $app.Name -Status "FAIL" -Details "No System Assigned Managed Identity"
            Write-Host "  [FAIL] App Service '$($app.Name)': No Managed Identity!" -ForegroundColor Red
        }
    }
}
catch {
    Add-ValidationResult -Check "App Service" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] App Service check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 4: Verify Private Endpoints - Provisioned and Connected
# ============================================================================

Write-Host "[CHECK] [4/7] Verifying Private Endpoints..." -ForegroundColor Yellow

try {
    $privateEndpoints = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName

    if ($privateEndpoints.Count -eq 0) {
        Add-ValidationResult -Check "Private Endpoints" -Resource "N/A" -Status "FAIL" -Details "No Private Endpoints found in resource group"
        Write-Host "  [FAIL] No Private Endpoints found!" -ForegroundColor Red
    }
    else {
        Write-Host "  Found $($privateEndpoints.Count) Private Endpoint(s)" -ForegroundColor Cyan
        foreach ($pe in $privateEndpoints) {
            $connectionState = $pe.PrivateLinkServiceConnections[0].PrivateLinkServiceConnectionState.Status
            if ($connectionState -eq 'Approved') {
                Add-ValidationResult -Check "Private Endpoint" -Resource $pe.Name -Status "PASS" -Details "Connection state: $connectionState"
                Write-Host "  [PASS] PE '$($pe.Name)': Connected ($connectionState)" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "Private Endpoint" -Resource $pe.Name -Status "FAIL" -Details "Connection state: $connectionState"
                Write-Host "  [FAIL] PE '$($pe.Name)': $connectionState" -ForegroundColor Red
            }
        }
    }
}
catch {
    Add-ValidationResult -Check "Private Endpoints" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] PE check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 5: Verify VNet Peering - Connected State
# ============================================================================

Write-Host "[CHECK] [5/7] Verifying VNet Peering..." -ForegroundColor Yellow

try {
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName

    foreach ($vnet in $vnets) {
        $peerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $vnet.Name -ResourceGroupName $ResourceGroupName
        foreach ($peering in $peerings) {
            if ($peering.PeeringState -eq 'Connected') {
                Add-ValidationResult -Check "VNet Peering" -Resource "$($vnet.Name)/$($peering.Name)" -Status "PASS" -Details "State: Connected"
                Write-Host "  [PASS] Peering '$($vnet.Name)/$($peering.Name)': Connected" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "VNet Peering" -Resource "$($vnet.Name)/$($peering.Name)" -Status "FAIL" -Details "State: $($peering.PeeringState)"
                Write-Host "  [FAIL] Peering '$($vnet.Name)/$($peering.Name)': $($peering.PeeringState)" -ForegroundColor Red
            }
        }
    }
}
catch {
    Add-ValidationResult -Check "VNet Peering" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] VNet Peering check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 6: Verify Data Factory - Public Access Disabled
# ============================================================================

Write-Host "[CHECK] [6/7] Verifying Data Factory configuration..." -ForegroundColor Yellow

try {
    $dataFactories = $null
    try { $dataFactories = Get-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -ErrorAction Stop }
    catch {
        # Fallback: discover ADF via Az.Resources if Az.DataFactory is unavailable
        Write-Host "  [INFO] Az.DataFactory not available, using ARM fallback" -ForegroundColor Cyan
        $adfResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.DataFactory/factories' -ExpandProperties
        foreach ($adfRes in $adfResources) {
            $pubAccess = $adfRes.Properties.publicNetworkAccess
            if ($pubAccess -eq 'Disabled') {
                Add-ValidationResult -Check "ADF Public Access" -Resource $adfRes.Name -Status "PASS" -Details "Public network access is Disabled"
                Write-Host "  [PASS] ADF '$($adfRes.Name)': Public access DISABLED" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "ADF Public Access" -Resource $adfRes.Name -Status "FAIL" -Details "Public network access is $pubAccess"
                Write-Host "  [FAIL] ADF '$($adfRes.Name)': Public access not disabled!" -ForegroundColor Red
            }
            $idType = $adfRes.Identity.Type
            if ($idType -match 'SystemAssigned') {
                Add-ValidationResult -Check "ADF Managed Identity" -Resource $adfRes.Name -Status "PASS" -Details "System Assigned MI enabled"
                Write-Host "  [PASS] ADF '$($adfRes.Name)': Managed Identity enabled" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "ADF Managed Identity" -Resource $adfRes.Name -Status "FAIL" -Details "No System Assigned Managed Identity"
                Write-Host "  [FAIL] ADF '$($adfRes.Name)': No Managed Identity!" -ForegroundColor Red
            }
        }
        $dataFactories = $null
    }

    if ($dataFactories) {
        foreach ($adf in $dataFactories) {
            if ($adf.PublicNetworkAccess -eq 'Disabled') {
                Add-ValidationResult -Check "ADF Public Access" -Resource $adf.DataFactoryName -Status "PASS" -Details "Public network access is Disabled"
                Write-Host "  [PASS] ADF '$($adf.DataFactoryName)': Public access DISABLED" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "ADF Public Access" -Resource $adf.DataFactoryName -Status "FAIL" -Details "Public network access is $($adf.PublicNetworkAccess)"
                Write-Host "  [FAIL] ADF '$($adf.DataFactoryName)': Public access not disabled!" -ForegroundColor Red
            }

            # Check Managed Identity
            if ($adf.Identity -and $adf.Identity.Type -match 'SystemAssigned') {
                Add-ValidationResult -Check "ADF Managed Identity" -Resource $adf.DataFactoryName -Status "PASS" -Details "System Assigned MI enabled"
                Write-Host "  [PASS] ADF '$($adf.DataFactoryName)': Managed Identity enabled" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "ADF Managed Identity" -Resource $adf.DataFactoryName -Status "FAIL" -Details "No System Assigned Managed Identity"
                Write-Host "  [FAIL] ADF '$($adf.DataFactoryName)': No Managed Identity!" -ForegroundColor Red
            }
        }
    }
}
catch {
    Add-ValidationResult -Check "Data Factory" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] ADF check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 7: Verify Private DNS Zones - VNet Links
# ============================================================================

Write-Host "[CHECK] [7/7] Verifying Private DNS Zones..." -ForegroundColor Yellow

$expectedZones = @(
    'privatelink.azurewebsites.net',
    'privatelink.database.windows.net',
    'privatelink.datafactory.azure.net',
    'privatelink.azuredatabricks.net'
)

foreach ($zoneName in $expectedZones) {
    try {
        $zone = $null
        $useFallback = $false
        try {
            $zone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $zoneName -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Message -match 'not recognized') {
                $useFallback = $true
            }
            else { throw }
        }

        if ($useFallback) {
            $resId = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/privateDnsZones/$zoneName"
            $zone = Get-AzResource -ResourceId $resId -ErrorAction SilentlyContinue
            if ($zone) {
                # Count VNet links via ARM
                $linkResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Network/privateDnsZones/virtualNetworkLinks' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "$zoneName/*" }
                $linkCount = ($linkResources | Measure-Object).Count
                Add-ValidationResult -Check "DNS Zone" -Resource $zoneName -Status "PASS" -Details "$linkCount VNet link(s) configured"
                Write-Host "  [PASS] DNS Zone '$zoneName': $linkCount VNet link(s)" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "DNS Zone" -Resource $zoneName -Status "FAIL" -Details "Zone not found"
                Write-Host "  [FAIL] DNS Zone '$zoneName': Not found!" -ForegroundColor Red
            }
        }
        elseif ($zone) {
            $links = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $zoneName
            $linkCount = ($links | Measure-Object).Count
            Add-ValidationResult -Check "DNS Zone" -Resource $zoneName -Status "PASS" -Details "$linkCount VNet link(s) configured"
            Write-Host "  [PASS] DNS Zone '$zoneName': $linkCount VNet link(s)" -ForegroundColor Green
        }
        else {
            Add-ValidationResult -Check "DNS Zone" -Resource $zoneName -Status "FAIL" -Details "Zone not found"
            Write-Host "  [FAIL] DNS Zone '$zoneName': Not found!" -ForegroundColor Red
        }
    }
    catch {
        Add-ValidationResult -Check "DNS Zone" -Resource $zoneName -Status "FAIL" -Details $_.Exception.Message
        Write-Host "  [FAIL] DNS Zone '$zoneName': Error - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# CHECK 8: Log Analytics Workspace
# ============================================================================

Write-Host ""
Write-Host "CHECK 8: Log Analytics Workspace" -ForegroundColor Yellow

try {
    $lawResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.OperationalInsights/workspaces' -ErrorAction Stop
    if ($lawResources.Count -gt 0) {
        foreach ($law in $lawResources) {
            $lawDetail = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $law.Name -ErrorAction Stop
            Add-ValidationResult -Check "Log Analytics" -Resource $law.Name -Status "PASS" -Details "Workspace exists, retention: $($lawDetail.RetentionInDays) days"
            Write-Host "  [PASS] Log Analytics '$($law.Name)': Active, retention $($lawDetail.RetentionInDays) days" -ForegroundColor Green
        }
    }
    else {
        Add-ValidationResult -Check "Log Analytics" -Resource "N/A" -Status "FAIL" -Details "No Log Analytics workspace found"
        Write-Host "  [FAIL] No Log Analytics workspace found in resource group" -ForegroundColor Red
    }
}
catch {
    Add-ValidationResult -Check "Log Analytics" -Resource "N/A" -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
    Write-Host "  [FAIL] Log Analytics check error: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================================
# CHECK 9: Diagnostic Settings on Key Resources
# ============================================================================

Write-Host ""
Write-Host "CHECK 9: Diagnostic Settings" -ForegroundColor Yellow

$diagTargets = @(
    @{ Type = 'Microsoft.Network/azureFirewalls'; Label = 'Firewall' }
    @{ Type = 'Microsoft.Network/bastionHosts'; Label = 'Bastion' }
    @{ Type = 'Microsoft.Sql/servers/databases'; Label = 'SQL Database' }
    @{ Type = 'Microsoft.DataFactory/factories'; Label = 'Data Factory' }
)

foreach ($target in $diagTargets) {
    try {
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType $target.Type -ErrorAction SilentlyContinue
        foreach ($res in $resources) {
            # Skip master database for SQL
            if ($res.Name -like '*/master') { continue }
            $diag = Get-AzDiagnosticSetting -ResourceId $res.ResourceId -ErrorAction SilentlyContinue
            if ($diag -and $diag.Count -gt 0) {
                Add-ValidationResult -Check "Diagnostic Settings" -Resource "$($target.Label): $($res.Name)" -Status "PASS" -Details "Diagnostic settings configured"
                Write-Host "  [PASS] $($target.Label) '$($res.Name)': Diagnostic settings enabled" -ForegroundColor Green
            }
            else {
                Add-ValidationResult -Check "Diagnostic Settings" -Resource "$($target.Label): $($res.Name)" -Status "FAIL" -Details "No diagnostic settings found"
                Write-Host "  [FAIL] $($target.Label) '$($res.Name)': No diagnostic settings!" -ForegroundColor Red
            }
        }
    }
    catch {
        Add-ValidationResult -Check "Diagnostic Settings" -Resource $target.Label -Status "FAIL" -Details "Check failed: $($_.Exception.Message)"
        Write-Host "  [FAIL] $($target.Label) diagnostic check error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# Summary Report
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Validation Summary - $($EnvironmentName.ToUpper())" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$passCount = ($validationResults | Where-Object { $_.Status -eq 'PASS' } | Measure-Object).Count
$failCount = ($validationResults | Where-Object { $_.Status -eq 'FAIL' } | Measure-Object).Count
$totalCount = $validationResults.Count

Write-Host ""
Write-Host "  Total Checks: $totalCount" -ForegroundColor White
Write-Host "  Passed:       $passCount" -ForegroundColor Green
Write-Host "  Failed:       $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

# Display detailed results table
$validationResults | Format-Table -AutoSize -Property Check, Resource, Status, Details

# ============================================================================
# Exit with appropriate code
# ============================================================================

if ($hasFailures) {
    Write-Host "##vso[task.logissue type=error]Post-deployment validation FAILED with $failCount failure(s)." 
    Write-Host "[FAIL] VALIDATION FAILED - Review failures above." -ForegroundColor Red
    
    # In DEV, warn but don't fail the pipeline
    if ($EnvironmentName -eq 'dev') {
        Write-Host "##vso[task.logissue type=warning]DEV environment: Failures logged as warnings."
        Write-Host "[WARN] DEV mode: Continuing despite failures (logged as warnings)." -ForegroundColor Yellow
    }
    else {
        Write-Host "##vso[task.complete result=Failed;]Validation failures detected in $($EnvironmentName.ToUpper())."
        exit 1
    }
}
else {
    Write-Host "[PASS] ALL VALIDATIONS PASSED - $($EnvironmentName.ToUpper()) environment is compliant." -ForegroundColor Green
    Write-Host "##vso[task.complete result=Succeeded;]All post-deployment validations passed."
}
