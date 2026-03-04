// Spoke Virtual Network

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Spoke VNet address space (CIDR)')
param spokeVnetAddressPrefix string

@description('App Service VNet integration subnet prefix')
param appServiceSubnetPrefix string

@description('Private Endpoints subnet prefix')
param privateEndpointSubnetPrefix string

@description('Databricks host (public) subnet prefix')
param databricksHostSubnetPrefix string

@description('Databricks container (private) subnet prefix')
param databricksContainerSubnetPrefix string

@description('Resource tags for governance and cost tracking')
param tags object

var spokeVnetName = 'vnet-spoke-${environmentName}'

// Network Security Group - Default (for App Service and Private Endpoints)

resource defaultNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-default-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Network Security Group - Databricks

resource databricksNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-databricks-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // ── Inbound Rules ──
      {
        name: 'AllowVNetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowAzureDatabricksControlPlaneInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureDatabricks'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      // ── Outbound Rules ──
      {
        name: 'AllowVNetOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowAzureDatabricksControlPlaneOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureDatabricks'
        }
      }
      {
        name: 'AllowSqlOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
        }
      }
      {
        name: 'AllowEventHubOutbound'
        properties: {
          priority: 140
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9093'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'EventHub'
        }
      }
    ]
  }
}

// Spoke Virtual Network

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: spokeVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app-service-${environmentName}'
        properties: {
          addressPrefix: appServiceSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Web-serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          networkSecurityGroup: {
            id: defaultNsg.id
          }
        }
      }
      {
        name: 'snet-private-endpoints-${environmentName}'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: defaultNsg.id
          }
        }
      }
      {
        name: 'snet-databricks-host-${environmentName}'
        properties: {
          addressPrefix: databricksHostSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Databricks-workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
          networkSecurityGroup: {
            id: databricksNsg.id
          }
        }
      }
      {
        name: 'snet-databricks-container-${environmentName}'
        properties: {
          addressPrefix: databricksContainerSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Databricks-workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
          networkSecurityGroup: {
            id: databricksNsg.id
          }
        }
      }
    ]
  }
}

// Existing subnet references

resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: spokeVnet
  name: 'snet-app-service-${environmentName}'
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: spokeVnet
  name: 'snet-private-endpoints-${environmentName}'
}

resource databricksHostSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: spokeVnet
  name: 'snet-databricks-host-${environmentName}'
}

resource databricksContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: spokeVnet
  name: 'snet-databricks-container-${environmentName}'
}

// Outputs

@description('Spoke VNet resource ID')
output spokeVnetId string = spokeVnet.id

@description('Spoke VNet name')
output spokeVnetName string = spokeVnet.name

@description('App Service VNet integration subnet ID')
output appServiceSubnetId string = appServiceSubnet.id

@description('Private Endpoints subnet ID')
output privateEndpointSubnetId string = privateEndpointSubnet.id

@description('Databricks host subnet name (needed for workspace config)')
output databricksHostSubnetName string = databricksHostSubnet.name

@description('Databricks container subnet name (needed for workspace config)')
output databricksContainerSubnetName string = databricksContainerSubnet.name
