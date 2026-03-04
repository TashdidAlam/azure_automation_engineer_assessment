# Task 1.3 -- Bicep Deployment

This document explains the Bicep templates, how they are structured, and what each module deploys.

## Project Layout

```
infra/
  main.bicep                          Orchestrator (wires all modules together)
  parameters/
    dev.bicepparam                    DEV environment values
    stg.bicepparam                    STG environment values
    prod.bicepparam                   PROD environment values
  modules/
    networking/
      hub-vnet.bicep                  Hub VNet with Bastion and Firewall subnets
      spoke-vnet.bicep                Spoke VNet with App, PE, Databricks subnets
      vnet-peering.bicep              Bidirectional Hub-Spoke peering
      private-dns-zones.bicep         Four Private DNS zones with VNet links
      bastion.bicep                   Azure Bastion (Standard SKU) + public IP
      firewall.bicep                  Azure Firewall + policy + rules
    compute/
      app-service.bicep               App Service Plan + Web App
      databricks.bicep                Databricks workspace (VNet injected, NPIP)
    data/
      sql-server.bicep                SQL logical server + database
      data-factory.bicep              ADF with Managed VNet + Managed IR
    identity/
      rbac.bicep                      Generic role assignment module
    security/
      private-endpoint.bicep          Generic PE module with DNS zone group
      policy.bicep                    Azure Policy assignments
      defender.bicep                  Defender for Cloud pricing plans (subscription scope)
    monitoring/
      log-analytics.bicep             Log Analytics workspace
      diagnostic-settings.bicep       Diagnostic settings for all resources
```

## How main.bicep Works

The orchestrator deploys resources in dependency order using `dependsOn`:

1. Hub VNet and Spoke VNet go first (no dependencies, deployed in parallel)
2. VNet Peering and Private DNS Zones come next (they need both VNets)
3. Bastion and Firewall depend on the Hub VNet subnets
4. App Service and Databricks depend on peering being established; SQL Server and Data Factory have no peering dependency
5. Private Endpoints depend on the services existing plus the DNS zones and PE subnet
6. RBAC assignments depend on the Managed Identity principal IDs from each service
7. Policy assignments are independent and go last
8. Log Analytics workspace deploys independently (no dependencies)
9. Diagnostic settings depend on all services + Log Analytics being ready
10. Defender pricing plans deploy at subscription scope (depends on Log Analytics)

## Conditional Deployments

Four boolean parameters control optional features:

- `deployAppService` -- set to false if the region has no VM compute quota (App Service needs it)
- `deployRbac` -- set to false if the service principal does not have User Access Administrator role
- `deployPolicies` -- set to false if the service principal does not have Resource Policy Contributor role
- `deployMonitoring` -- set to false to skip Log Analytics, diagnostic settings, and Defender data collection

This allows the same template to work across environments with different permission levels.

## Region Override Parameters

Sometimes a region has quota or provisioning restrictions for specific services. Two override parameters handle this:

- `sqlLocation` -- defaults to the main `location`, but can target a different region for SQL
- `appServiceLocation` -- defaults to `location`, can redirect App Service to a region with VM quota

## Module Details

**hub-vnet.bicep** creates the Hub VNet with AzureBastionSubnet and AzureFirewallSubnet. It also creates the Bastion NSG with Azure-required rules.

**spoke-vnet.bicep** creates the Spoke VNet with four subnets: App Service (delegated), Private Endpoints, Databricks host (delegated), and Databricks container (delegated). Each gets its own NSG.

**vnet-peering.bicep** establishes bidirectional peering between Hub and Spoke. Both directions allow forwarded traffic.

**private-dns-zones.bicep** creates four zones (azurewebsites.net, database.windows.net, datafactory.azure.net, azuredatabricks.net) and links each to both VNets. The SQL zone uses `environment().suffixes.sqlServerHostname` for sovereign cloud compatibility.

**bastion.bicep** deploys Azure Bastion with Standard SKU, tunneling and file copy enabled, plus its public IP.

**firewall.bicep** deploys Azure Firewall Standard with a firewall policy, network rules (SQL, Storage, Monitor, KeyVault service tags), and application rules (Microsoft/Azure endpoints, Databricks control plane). Threat intelligence is in Deny mode.

**app-service.bicep** creates a Linux App Service Plan and Web App running .NET 8. Public access is disabled, HTTPS is enforced, FTPS is off, TLS 1.2 minimum, VNet integration is enabled, and a System Assigned Managed Identity is created.

**databricks.bicep** creates a Premium-tier workspace with VNet injection into the spoke subnets. NPIP mode ensures clusters have no public IPs. Public access to the workspace is disabled.

**sql-server.bicep** creates a SQL logical server with Entra-only authentication (no SQL passwords). Public access is disabled, TLS 1.2 minimum. It creates a database with environment-appropriate SKU and backup settings.

**data-factory.bicep** creates an ADF instance with Managed VNet and a Managed Integration Runtime (AutoResolve). Public access is disabled and a System Assigned Managed Identity is enabled.

**rbac.bicep** is a reusable module that creates a single role assignment. It uses `guid(resourceGroup().id, principalId, roleDefinitionId)` to generate a deterministic name, making it idempotent on re-deployment.

**private-endpoint.bicep** is a reusable module for creating a PE. It takes the target resource ID, group ID, subnet ID, and DNS zone ID. A DNS zone group auto-registers the A-record.

**policy.bicep** assigns four built-in Azure Policies (deny public access on SQL, App Service, ADF; audit PE configuration) at the Resource Group scope.

**log-analytics.bicep** creates a Log Analytics workspace (PerGB2018 SKU). Retention is configurable per environment (30 days DEV, 60 days STG, 90 days PROD). DEV has a 1 GB/day ingestion cap to control costs.

**diagnostic-settings.bicep** attaches diagnostic settings to all deployed resources (SQL Database, Azure Firewall, Bastion, Databricks, Data Factory, App Service). All logs and metrics route to the central Log Analytics workspace. Uses `existing` keyword to reference resources deployed by other modules.

**defender.bicep** enables Microsoft Defender for Cloud pricing plans (Free tier) at subscription scope for SQL, App Services, Containers, Storage, Key Vault, ARM, open-source databases, and Cosmos DB. This provides security assessments and recommendations without additional cost.

## Parameter Files

All three parameter files have the same structure. The only differences are the actual values:

- Environment name (dev/stg/prod)
- Region (westus3 for all environments -- single region due to subscription constraints)
- VNet address spaces (non-overlapping per environment, designed for future subscription migration)
- Service SKUs (B1/Basic for DEV, S1/S1 for STG and PROD -- S1 due to subscription quota limits on Premium SKUs)
- Feature flags (`deployRbac = true` in all environments -- service principal has User Access Administrator scoped to each RG)
- Monitoring retention (30 days DEV, 60 days STG, 90 days PROD)
- Tags (PROD adds Criticality and DataClassification)

The idea is that the Bicep template is identical across environments. You promote code through dev, staging, and production branches, and only the parameter file changes. SKU and region values can be upgraded per-environment when subscription constraints are lifted.
