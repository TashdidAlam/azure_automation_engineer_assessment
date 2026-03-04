// Parameters

@description('Target environment')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Azure region for all resources')
param location string

@description('Azure region for SQL Server (defaults to location; override if region blocks SQL provisioning)')
param sqlLocation string = location

@description('Azure region for App Service (defaults to location; override if region has no VM compute quota)')
param appServiceLocation string = location

@description('Hub VNet address space')
param hubVnetAddressPrefix string

@description('Azure Bastion subnet prefix (minimum /26)')
param bastionSubnetAddressPrefix string

@description('Azure Firewall subnet prefix (minimum /26)')
param firewallSubnetAddressPrefix string

@description('Spoke VNet address space')
param spokeVnetAddressPrefix string

@description('App Service VNet integration subnet prefix')
param appServiceSubnetPrefix string

@description('Private Endpoints subnet prefix')
param privateEndpointSubnetPrefix string

@description('Databricks host subnet prefix')
param databricksHostSubnetPrefix string

@description('Databricks container subnet prefix')
param databricksContainerSubnetPrefix string

@description('App Service Plan SKU')
param appServicePlanSku string

@description('SQL Database SKU')
param sqlDatabaseSku string

@description('Databricks workspace pricing tier')
@allowed(['standard', 'premium'])
param databricksSku string

@description('Object ID of the Entra ID admin for SQL Server')
param entraAdminObjectId string

@description('Display name of the Entra ID admin for SQL Server')
param entraAdminDisplayName string

@description('Resource tags applied to all resources')
param tags object

@description('Deploy App Service (requires VM compute quota - set false if quota is 0)')
param deployAppService bool = true

@description('Deploy Azure Policy assignments (requires Resource Policy Contributor role)')
param deployPolicies bool = true

@description('Deploy RBAC role assignments (requires User Access Administrator or Owner role)')
param deployRbac bool = true

@description('Deploy monitoring (Log Analytics, Diagnostic Settings, Defender)')
param deployMonitoring bool = true

@description('Log Analytics log retention period in days')
param logRetentionDays int = 30

module hubVnet 'modules/networking/hub-vnet.bicep' = {
  name: 'deploy-hub-vnet-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    hubVnetAddressPrefix: hubVnetAddressPrefix
    bastionSubnetAddressPrefix: bastionSubnetAddressPrefix
    firewallSubnetAddressPrefix: firewallSubnetAddressPrefix
    tags: tags
  }
}

module spokeVnet 'modules/networking/spoke-vnet.bicep' = {
  name: 'deploy-spoke-vnet-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    spokeVnetAddressPrefix: spokeVnetAddressPrefix
    appServiceSubnetPrefix: appServiceSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    databricksHostSubnetPrefix: databricksHostSubnetPrefix
    databricksContainerSubnetPrefix: databricksContainerSubnetPrefix
    tags: tags
  }
}

module vnetPeering 'modules/networking/vnet-peering.bicep' = {
  name: 'deploy-vnet-peering-${environmentName}'
  params: {
    hubVnetName: hubVnet.outputs.hubVnetName
    spokeVnetName: spokeVnet.outputs.spokeVnetName
    hubVnetId: hubVnet.outputs.hubVnetId
    spokeVnetId: spokeVnet.outputs.spokeVnetId
  }
}

module privateDnsZones 'modules/networking/private-dns-zones.bicep' = {
  name: 'deploy-private-dns-zones-${environmentName}'
  params: {
    tags: tags
    hubVnetId: hubVnet.outputs.hubVnetId
    spokeVnetId: spokeVnet.outputs.spokeVnetId
  }
}

module bastion 'modules/networking/bastion.bicep' = {
  name: 'deploy-bastion-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    tags: tags
    bastionSubnetId: hubVnet.outputs.bastionSubnetId
  }
}

module firewall 'modules/networking/firewall.bicep' = {
  name: 'deploy-firewall-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    tags: tags
    firewallSubnetId: hubVnet.outputs.firewallSubnetId
    spokeVnetAddressPrefix: spokeVnetAddressPrefix
  }
}

module appService 'modules/compute/app-service.bicep' = if (deployAppService) {
  name: 'deploy-app-service-${environmentName}'
  params: {
    location: appServiceLocation
    environmentName: environmentName
    tags: tags
    appServicePlanSku: appServicePlanSku
    vnetIntegrationSubnetId: appServicePlanSku == 'F1' || appServicePlanSku == 'D1' ? '' : spokeVnet.outputs.appServiceSubnetId
  }
  dependsOn: [
    vnetPeering
  ]
}

module sqlServer 'modules/data/sql-server.bicep' = {
  name: 'deploy-sql-server-${environmentName}'
  params: {
    location: sqlLocation
    environmentName: environmentName
    tags: tags
    sqlDatabaseSku: sqlDatabaseSku
    entraAdminObjectId: entraAdminObjectId
    entraAdminDisplayName: entraAdminDisplayName
  }
}

module dataFactory 'modules/data/data-factory.bicep' = {
  name: 'deploy-data-factory-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    tags: tags
  }
}

module databricks 'modules/compute/databricks.bicep' = {
  name: 'deploy-databricks-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    tags: tags
    databricksSku: databricksSku
    spokeVnetId: spokeVnet.outputs.spokeVnetId
    databricksHostSubnetName: spokeVnet.outputs.databricksHostSubnetName
    databricksContainerSubnetName: spokeVnet.outputs.databricksContainerSubnetName
  }
  dependsOn: [
    vnetPeering
  ]
}

module pepAppService 'modules/security/private-endpoint.bicep' = if (deployAppService && appServicePlanSku != 'F1' && appServicePlanSku != 'D1') {
  name: 'deploy-pep-app-service-${environmentName}'
  params: {
    location: location
    name: 'pep-app-service-${environmentName}'
    tags: tags
    privateLinkServiceId: appService!.outputs.webAppId
    groupIds: ['sites']
    subnetId: spokeVnet.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDnsZones.outputs.appServiceDnsZoneId
  }
}

module pepSqlServer 'modules/security/private-endpoint.bicep' = {
  name: 'deploy-pep-sql-server-${environmentName}'
  params: {
    location: location
    name: 'pep-sql-server-${environmentName}'
    tags: tags
    privateLinkServiceId: sqlServer.outputs.sqlServerId
    groupIds: ['sqlServer']
    subnetId: spokeVnet.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDnsZones.outputs.sqlDnsZoneId
  }
}

module pepDataFactory 'modules/security/private-endpoint.bicep' = {
  name: 'deploy-pep-data-factory-${environmentName}'
  params: {
    location: location
    name: 'pep-data-factory-${environmentName}'
    tags: tags
    privateLinkServiceId: dataFactory.outputs.dataFactoryId
    groupIds: ['dataFactory']
    subnetId: spokeVnet.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDnsZones.outputs.dataFactoryDnsZoneId
  }
}

module pepDatabricks 'modules/security/private-endpoint.bicep' = {
  name: 'deploy-pep-databricks-${environmentName}'
  params: {
    location: location
    name: 'pep-databricks-${environmentName}'
    tags: tags
    privateLinkServiceId: databricks.outputs.databricksId
    groupIds: ['databricks_ui_api']
    subnetId: spokeVnet.outputs.privateEndpointSubnetId
    privateDnsZoneId: privateDnsZones.outputs.databricksDnsZoneId
  }
}

module rbacAppServiceToSql 'modules/identity/rbac.bicep' = if (deployRbac && deployAppService) {
  name: 'deploy-rbac-app-to-sql-${environmentName}'
  params: {
    principalId: appService!.outputs.webAppPrincipalId
    roleDefinitionId: '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec'
    principalType: 'ServicePrincipal'
    roleAssignmentDescription: 'App Service Managed Identity -> SQL DB Contributor'
  }
}

module rbacDataFactoryContributor 'modules/identity/rbac.bicep' = if (deployRbac) {
  name: 'deploy-rbac-adf-contributor-${environmentName}'
  params: {
    principalId: dataFactory.outputs.dataFactoryPrincipalId
    roleDefinitionId: '673868aa-7521-48a0-acc6-0f60742d39f5'
    principalType: 'ServicePrincipal'
    roleAssignmentDescription: 'Data Factory Managed Identity -> Data Factory Contributor (for pipeline orchestration)'
  }
}

module rbacDataFactoryToSql 'modules/identity/rbac.bicep' = if (deployRbac) {
  name: 'deploy-rbac-adf-to-sql-${environmentName}'
  params: {
    principalId: dataFactory.outputs.dataFactoryPrincipalId
    roleDefinitionId: '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec'
    principalType: 'ServicePrincipal'
    roleAssignmentDescription: 'Data Factory Managed Identity -> SQL DB Contributor'
  }
}

module policyAssignments 'modules/security/policy.bicep' = if (deployPolicies) {
  name: 'deploy-policy-assignments-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Monitoring and Security

module logAnalytics 'modules/monitoring/log-analytics.bicep' = if (deployMonitoring) {
  name: 'deploy-log-analytics-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    tags: tags
    retentionDays: logRetentionDays
  }
}

module diagnosticSettings 'modules/monitoring/diagnostic-settings.bicep' = if (deployMonitoring) {
  name: 'deploy-diagnostic-settings-${environmentName}'
  params: {
    logAnalyticsWorkspaceId: logAnalytics!.outputs.workspaceId
    environmentName: environmentName
    deployAppService: deployAppService
  }
  dependsOn: [
    sqlServer
    firewall
    bastion
    databricks
    dataFactory
    appService
  ]
}

module defender 'modules/security/defender.bicep' = if (deployMonitoring) {
  name: 'deploy-defender-${environmentName}'
  scope: subscription()
  params: {
    logAnalyticsWorkspaceId: logAnalytics!.outputs.workspaceId
    environmentName: environmentName
  }
}

// Outputs

@description('Hub VNet resource ID')
output hubVnetId string = hubVnet.outputs.hubVnetId

@description('Spoke VNet resource ID')
output spokeVnetId string = spokeVnet.outputs.spokeVnetId

@description('Web App name')
output webAppName string = deployAppService ? appService!.outputs.webAppName : 'not-deployed'

@description('SQL Server fully qualified domain name')
output sqlServerFqdn string = sqlServer.outputs.sqlServerFqdn

@description('Data Factory name')
output dataFactoryName string = dataFactory.outputs.dataFactoryName

@description('Databricks workspace URL')
output databricksWorkspaceUrl string = databricks.outputs.databricksWorkspaceUrl

@description('Azure Firewall private IP (for UDR configuration)')
output firewallPrivateIp string = firewall.outputs.firewallPrivateIp

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceId string = deployMonitoring ? logAnalytics!.outputs.workspaceId : 'not-deployed'
