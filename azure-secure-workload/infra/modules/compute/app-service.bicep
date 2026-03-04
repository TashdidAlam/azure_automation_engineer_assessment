// App Service

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

@description('App Service Plan SKU name (e.g., F1, B1, S1, P1v3)')
param appServicePlanSku string

@description('Subnet resource ID for VNet Integration (outbound). Empty string disables VNet integration.')
param vnetIntegrationSubnetId string = ''

// Variables

var appServicePlanName = 'asp-secure-workload-${environmentName}'
var webAppName = 'app-secure-workload-${environmentName}-${uniqueString(resourceGroup().id)}'

var isFreeTier = toLower(appServicePlanSku) == 'f1' || toLower(appServicePlanSku) == 'd1'
var enableVnetIntegration = !isFreeTier && !empty(vnetIntegrationSubnetId)

// App Service Plan - Linux

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true
  }
}

// Web App

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: isFreeTier ? 'Enabled' : 'Disabled'
    httpsOnly: true
    virtualNetworkSubnetId: enableVnetIntegration ? vnetIntegrationSubnetId : null
    siteConfig: {
      vnetRouteAllEnabled: enableVnetIntegration
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: !isFreeTier
      linuxFxVersion: 'DOTNETCORE|8.0'
      healthCheckPath: '/health'
    }
  }
}

// Outputs

@description('Web App resource ID (for Private Endpoint creation)')
output webAppId string = webApp.id

@description('Web App name')
output webAppName string = webApp.name

@description('System Assigned Managed Identity principal ID (for RBAC)')
output webAppPrincipalId string = webApp.identity.principalId

@description('Default hostname of the Web App')
output webAppDefaultHostname string = webApp.properties.defaultHostName

@description('Indicates whether the SKU supports Private Endpoints')
output supportsPrivateEndpoint bool = !isFreeTier
