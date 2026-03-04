@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Whether App Service is deployed')
param deployAppService bool = true

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' existing = {
  name: 'sql-secure-workload-${environmentName}-${uniqueString(resourceGroup().id)}'
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = {
  parent: sqlServer
  name: 'sqldb-secure-workload-${environmentName}'
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
  name: 'afw-hub-${environmentName}'
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' existing = {
  name: 'bas-hub-${environmentName}'
}

resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' existing = {
  name: 'dbw-secure-workload-${environmentName}'
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: 'adf-secure-wl-${environmentName}-${uniqueString(resourceGroup().id)}'
}

resource sqlDbDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-sqldb-to-law'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'Basic', enabled: true }
      { category: 'InstanceAndAppAdvanced', enabled: true }
      { category: 'WorkloadManagement', enabled: true }
    ]
  }
}

resource firewallDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-firewall-to-law'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Azure Bastion - session and audit logs
resource bastionDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-bastion-to-law'
  scope: bastion
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Databricks - workspace and cluster logs
resource databricksDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-databricks-to-law'
  scope: databricks
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
  }
}

// Data Factory - pipeline and trigger logs
resource dataFactoryDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-adf-to-law'
  scope: dataFactory
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// App Service - conditional
resource webApp 'Microsoft.Web/sites@2023-12-01' existing = if (deployAppService) {
  name: 'app-secure-workload-${environmentName}-${uniqueString(resourceGroup().id)}'
}

resource webAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployAppService) {
  name: 'diag-webapp-to-law'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AppServiceHTTPLogs', enabled: true }
      { category: 'AppServiceConsoleLogs', enabled: true }
      { category: 'AppServiceAppLogs', enabled: true }
      { category: 'AppServicePlatformLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}
