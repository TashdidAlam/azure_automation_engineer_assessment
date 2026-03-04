targetScope = 'subscription'

@description('Log Analytics workspace resource ID for security data collection')
param logAnalyticsWorkspaceId string

@description('Environment identifier (used for description only)')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

resource defenderForSql 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'SqlServers'
  properties: {
    pricingTier: 'Free'
  }
}

resource defenderForAppService 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'AppServices'
  properties: {
    pricingTier: 'Free'
  }
}

resource defenderForArm 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'Arm'
  properties: {
    pricingTier: 'Free'
  }
}

resource autoProvisionLogAnalytics 'Microsoft.Security/autoProvisioningSettings@2017-08-01-preview' = {
  name: 'default'
  properties: {
    autoProvision: 'Off'
  }
}

resource workspaceSettings 'Microsoft.Security/workspaceSettings@2017-08-01-preview' = {
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    scope: subscription().id
  }
}

// Outputs

@description('Defender for SQL plan tier')
output defenderSqlTier string = defenderForSql.properties.pricingTier

@description('Defender for App Service plan tier')
output defenderAppServiceTier string = defenderForAppService.properties.pricingTier

@description('Environment this was deployed for')
output environment string = environmentName
