// Hub Virtual Network

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Hub VNet address space (CIDR)')
param hubVnetAddressPrefix string

@description('Azure Bastion subnet address prefix (minimum /26)')
param bastionSubnetAddressPrefix string

@description('Azure Firewall subnet address prefix (minimum /26)')
param firewallSubnetAddressPrefix string

@description('Resource tags for governance and cost tracking')
param tags object

var hubVnetName = 'vnet-hub-${environmentName}'

// Network Security Group - Azure Bastion

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-bastion-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // ── Inbound Rules ──
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowBastionHostCommunicationInbound'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      // ── Outbound Rules ──
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
      {
        name: 'AllowBastionHostCommunicationOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowGetSessionInformationOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

// Hub Virtual Network

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: hubVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetAddressPrefix
          networkSecurityGroup: {
            id: bastionNsg.id
          }
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetAddressPrefix
        }
      }
    ]
  }
}

// Existing subnet references

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: hubVnet
  name: 'AzureBastionSubnet'
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: hubVnet
  name: 'AzureFirewallSubnet'
}

// Outputs

@description('Hub VNet resource ID')
output hubVnetId string = hubVnet.id

@description('Hub VNet name')
output hubVnetName string = hubVnet.name

@description('Azure Bastion subnet resource ID')
output bastionSubnetId string = bastionSubnet.id

@description('Azure Firewall subnet resource ID')
output firewallSubnetId string = firewallSubnet.id
