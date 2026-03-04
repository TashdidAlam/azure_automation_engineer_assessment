using '../main.bicep'

param environmentName = 'dev'
param location = 'westus3'
param sqlLocation = 'westus3'
param appServiceLocation = 'westus3'

param hubVnetAddressPrefix = '10.0.0.0/16'
param bastionSubnetAddressPrefix = '10.0.0.0/26'
param firewallSubnetAddressPrefix = '10.0.1.0/26'

param spokeVnetAddressPrefix = '10.1.0.0/16'
param appServiceSubnetPrefix = '10.1.1.0/24'
param privateEndpointSubnetPrefix = '10.1.2.0/24'
param databricksHostSubnetPrefix = '10.1.3.0/24'
param databricksContainerSubnetPrefix = '10.1.4.0/24'

param appServicePlanSku = 'B1'
param sqlDatabaseSku = 'Basic'
param databricksSku = 'premium'

param deployAppService = true

param deployPolicies = true

// Service principal has User Access Administrator scoped to each environment RG
param deployRbac = true

param deployMonitoring = true
param logRetentionDays = 30

param entraAdminObjectId = '5eadddb3-78f7-4efd-af3d-4db983f695fb'
param entraAdminDisplayName = 'sql-admin'

param tags = {
  Environment: 'dev'
  Project: 'Azure Secure Workload'
  ManagedBy: 'Bicep'
  CostCenter: 'Engineering'
  Owner: 'Platform Engineering'
}
