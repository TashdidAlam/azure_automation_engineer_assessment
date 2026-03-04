// Azure Data Factory

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

// Variables

var dataFactoryName = 'adf-secure-wl-${environmentName}-${uniqueString(resourceGroup().id)}'

// Azure Data Factory

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

// Managed Virtual Network

resource managedVnet 'Microsoft.DataFactory/factories/managedVirtualNetworks@2018-06-01' = {
  parent: dataFactory
  name: 'default'
  properties: {}
}

// Managed Integration Runtime

resource managedIntegrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: dataFactory
  name: 'ManagedVNetIntegrationRuntime'
  properties: {
    type: 'Managed'
    managedVirtualNetwork: {
      referenceName: 'default'
      type: 'ManagedVirtualNetworkReference'
    }
    typeProperties: {
      computeProperties: {
        location: 'AutoResolve'
        dataFlowProperties: {
          computeType: 'General'
          coreCount: 8
          timeToLive: 10
        }
      }
    }
  }
  dependsOn: [
    managedVnet
  ]
}

// Outputs

@description('Data Factory resource ID (for Private Endpoint creation)')
output dataFactoryId string = dataFactory.id

@description('Data Factory name')
output dataFactoryName string = dataFactory.name

@description('Data Factory System Assigned Managed Identity principal ID')
output dataFactoryPrincipalId string = dataFactory.identity.principalId
