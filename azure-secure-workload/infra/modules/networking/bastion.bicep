// Azure Bastion

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

@description('Resource ID of the AzureBastionSubnet')
param bastionSubnetId string

// Variables

var bastionName = 'bas-hub-${environmentName}'
var bastionPipName = 'pip-bastion-${environmentName}'

// Public IP Address for Azure Bastion

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: bastionPipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Bastion Host

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    enableFileCopy: true
    enableShareableLink: false
    ipConfigurations: [
      {
        name: 'bastion-ip-config'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

// Outputs

@description('Azure Bastion resource ID')
output bastionId string = bastion.id

@description('Azure Bastion name')
output bastionName string = bastion.name
