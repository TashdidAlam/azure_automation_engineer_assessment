// VNet Peering

@description('Name of the Hub VNet')
param hubVnetName string

@description('Name of the Spoke VNet')
param spokeVnetName string

@description('Resource ID of the Hub VNet')
param hubVnetId string

@description('Resource ID of the Spoke VNet')
param spokeVnetId string

// Existing VNet references

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: hubVnetName
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: spokeVnetName
}

resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spokeVnet
  name: 'peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Outputs

@description('Hub to Spoke peering resource ID')
output hubToSpokePeeringId string = hubToSpokePeering.id

@description('Spoke to Hub peering resource ID')
output spokeToHubPeeringId string = spokeToHubPeering.id
