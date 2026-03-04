using '../main.bicep'

param environmentName = 'prod'
param location = 'westus3'
param sqlLocation = 'westus3'
param appServiceLocation = 'westus3'

param hubVnetAddressPrefix = '10.20.0.0/16'
param bastionSubnetAddressPrefix = '10.20.0.0/26'
param firewallSubnetAddressPrefix = '10.20.1.0/26'

param spokeVnetAddressPrefix = '10.21.0.0/16'
param appServiceSubnetPrefix = '10.21.1.0/24'
param privateEndpointSubnetPrefix = '10.21.2.0/24'
param databricksHostSubnetPrefix = '10.21.3.0/24'
param databricksContainerSubnetPrefix = '10.21.4.0/24'

param appServicePlanSku = 'S1'
param sqlDatabaseSku = 'S1'
param databricksSku = 'premium'

param deployAppService = true

param deployPolicies = true

// Service principal has User Access Administrator scoped to each environment RG
param deployRbac = true

param deployMonitoring = true
param logRetentionDays = 90

param entraAdminObjectId = '<YOUR-ENTRA-ADMIN-OBJECT-ID>'      // Replace with your Entra admin's Object ID
param entraAdminDisplayName = '<YOUR-ENTRA-ADMIN-DISPLAY-NAME>'  // Replace with your Entra admin's display name

param tags = {
  Environment: 'prod'
  Project: 'Azure Secure Workload'
  ManagedBy: 'Bicep'
  CostCenter: 'Operations'
  Owner: 'Platform Engineering'
  Criticality: 'Business Critical'
  DataClassification: 'Confidential'
}
