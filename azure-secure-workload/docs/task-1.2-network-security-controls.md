# Task 1.2 -- Network and Security Controls

This document lists the specific Azure configurations applied to ensure private-only communication across all services.

## Azure SQL -- No Public Access

- `publicNetworkAccess` is set to `Disabled` in the Bicep template
- A Private Endpoint (group ID: `sqlServer`) is created in the spoke PE subnet
- DNS is handled by the `privatelink.database.windows.net` zone
- SQL authentication is disabled entirely (`azureADOnlyAuthentication: true`)
- Only Entra ID users/groups and Managed Identities can authenticate
- Minimum TLS version is set to 1.2
- An Azure Policy (Deny effect) blocks creation of any SQL Server with public access enabled

## App Service -- No Inbound Public Traffic

- `publicNetworkAccess` is set to `Disabled`
- The app is VNet-integrated into the spoke subnet for outbound traffic
- A Private Endpoint (group ID: `sites`) handles inbound traffic
- DNS is handled by the `privatelink.azurewebsites.net` zone
- HTTPS is enforced (`httpsOnly: true`)
- FTPS is disabled (`ftpsState: 'Disabled'`)
- Minimum TLS version is 1.2
- A System Assigned Managed Identity is enabled for service-to-service auth
- An Azure Policy (Deny effect) blocks creation of any App Service with public access enabled

## Data Factory -- Private Dependencies Only

- `publicNetworkAccess` is set to `Disabled`
- A Managed Virtual Network is configured (`managedVirtualNetworkEnabled: true`)
- The Integration Runtime uses AutoResolve inside the Managed VNet
- A Private Endpoint (group ID: `dataFactory`) is created in the spoke PE subnet
- DNS is handled by the `privatelink.datafactory.azure.net` zone
- A System Assigned Managed Identity is used for all connections
- An Azure Policy (Deny effect) requires ADF to use Private Link

## Databricks -- Private Workspace

- `publicNetworkAccess` is set to `Disabled`
- The workspace is deployed with VNet injection (host and container subnets in the spoke)
- No Public IP (NPIP) mode is enabled -- clusters get only private IPs
- `requiredNsgRules` is set to `NoAzureDatabricksRules` for custom NSG control
- A Private Endpoint (group ID: `databricks_ui_api`) is created in the spoke PE subnet
- DNS is handled by the `privatelink.azuredatabricks.net` zone

## Network Segmentation

- Each subnet has a dedicated Network Security Group (NSG)
- Default inbound rule on App Service and PE subnets is Deny All
- Bastion NSG follows Azure-required rules (HTTPS inbound, SSH/RDP to VNet outbound)
- Databricks NSG allows worker-to-worker, control plane, and storage traffic

## Centralized Egress

- Azure Firewall (Standard SKU) is deployed in the Hub
- Threat intelligence is set to Deny mode (blocks known malicious IPs/domains)
- Network rules allow traffic to SQL, Storage, Monitor, and KeyVault service tags
- Application rules allow Microsoft and Azure endpoints plus the Databricks control plane
- Source addresses in firewall rules use the spoke VNet CIDR (parameterized per environment, not hardcoded)

## Azure Policy Guardrails

Four built-in policies are assigned at the Resource Group scope:

| Policy | Effect |
|--------|--------|
| Deny SQL Public Network Access | Deny |
| Deny App Service Public Access | Deny |
| Require ADF Private Link | Deny |
| Audit Private Endpoint Configuration | Audit |

In an enterprise setting, these policies should be assigned at the Management Group level to cover all subscriptions automatically. The current Resource Group scope is a limitation of deploying all environments within a single subscription.

## Post-Deployment Validation

After every deployment, a PowerShell script validates the security posture:

1. Resource group exists and has the expected resources
2. SQL Server public access is disabled and Entra admin is configured
3. App Service public access is disabled and Managed Identity is enabled
4. All Private Endpoints are in Approved connection state
5. VNet Peering is in Connected state (both directions)
6. Data Factory public access is disabled and Managed Identity is enabled
7. All four Private DNS Zones are linked to both Hub and Spoke VNets
8. Log Analytics workspace exists and retention matches the environment setting
9. Diagnostic settings are attached to Firewall, Bastion, SQL Database, and Data Factory

In STG and PROD, any validation failure stops the pipeline. In DEV, failures are logged as warnings.
