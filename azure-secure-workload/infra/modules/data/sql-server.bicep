// Azure SQL Server + Database

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

@description('SQL Database SKU name (e.g., Basic, S1, P2)')
param sqlDatabaseSku string

@description('Object ID of the Entra ID admin for SQL Server')
param entraAdminObjectId string

@description('Display name of the Entra ID admin for SQL Server')
param entraAdminDisplayName string

// Variables

var sqlServerName = 'sql-secure-workload-${environmentName}-${uniqueString(resourceGroup().id)}'
var sqlDatabaseName = 'sqldb-secure-workload-${environmentName}'

// Azure SQL Logical Server

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'

    administrators: {
      administratorType: 'ActiveDirectory'
      login: entraAdminDisplayName
      sid: entraAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// Azure SQL Database

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: sqlDatabaseSku
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Outputs

@description('SQL Server resource ID (for Private Endpoint creation)')
output sqlServerId string = sqlServer.id

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Server fully qualified domain name')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database resource ID')
output sqlDatabaseId string = sqlDatabase.id

@description('SQL Server System Assigned Managed Identity principal ID')
output sqlServerPrincipalId string = sqlServer.identity.principalId
