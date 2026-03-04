// Private Endpoint

@description('Azure region for resource deployment')
param location string

@description('Name of the Private Endpoint resource')
param name string

@description('Resource tags for governance and cost tracking')
param tags object

@description('Resource ID of the target PaaS service')
param privateLinkServiceId string

@description('Private Link sub-resource group IDs (e.g., sites, sqlServer, dataFactory, databricks_ui_api)')
param groupIds array

@description('Resource ID of the subnet where the PE NIC will be placed')
param subnetId string

@description('Resource ID of the Private DNS Zone for automatic A-record registration')
param privateDnsZoneId string

// Private Endpoint

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-plsc'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

// Private DNS Zone Group

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(name, '-', '')
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

@description('Private Endpoint resource ID')
output privateEndpointId string = privateEndpoint.id

@description('Private Endpoint name')
output privateEndpointName string = privateEndpoint.name
