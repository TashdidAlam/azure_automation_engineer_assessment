// Private DNS Zones

@description('Resource tags for governance and cost tracking')
param tags object

@description('Hub VNet resource ID for DNS zone linking')
param hubVnetId string

@description('Spoke VNet resource ID for DNS zone linking')
param spokeVnetId string

// Variables

var sqlDnsZoneName = 'privatelink${environment().suffixes.sqlServerHostname}'

var privateDnsZoneNames = [
  'privatelink.azurewebsites.net'
  sqlDnsZoneName
  'privatelink.datafactory.azure.net'
  'privatelink.azuredatabricks.net'
]

// Private DNS Zones

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zoneName in privateDnsZoneNames: {
    name: zoneName
    location: 'global'
    tags: tags
  }
]

// VNet Links - Hub VNet

resource hubVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, i) in privateDnsZoneNames: {
    parent: privateDnsZones[i]
    name: 'link-hub-vnet'
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: {
        id: hubVnetId
      }
      registrationEnabled: false
    }
  }
]

// VNet Links - Spoke VNet

resource spokeVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, i) in privateDnsZoneNames: {
    parent: privateDnsZones[i]
    name: 'link-spoke-vnet'
    location: 'global'
    tags: tags
    properties: {
      virtualNetwork: {
        id: spokeVnetId
      }
      registrationEnabled: false
    }
  }
]

// Outputs

@description('Private DNS Zone ID for App Service')
output appServiceDnsZoneId string = privateDnsZones[0].id

@description('Private DNS Zone ID for Azure SQL')
output sqlDnsZoneId string = privateDnsZones[1].id

@description('Private DNS Zone ID for Data Factory')
output dataFactoryDnsZoneId string = privateDnsZones[2].id

@description('Private DNS Zone ID for Databricks')
output databricksDnsZoneId string = privateDnsZones[3].id
