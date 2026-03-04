// Azure Firewall

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

@description('Resource ID of the AzureFirewallSubnet')
param firewallSubnetId string

@description('Spoke VNet address prefix for firewall rule source addresses')
param spokeVnetAddressPrefix string

// Variables

var firewallName = 'afw-hub-${environmentName}'
var firewallPipName = 'pip-firewall-${environmentName}'
var firewallPolicyName = 'afwp-hub-${environmentName}'

// Public IP Address for Azure Firewall

resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: firewallPipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Firewall Policy

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Deny'
  }
}

resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowAzureServices'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureSQL'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeVnetAddressPrefix]
            destinationAddresses: ['Sql']
            destinationPorts: ['1433']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureStorage'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeVnetAddressPrefix]
            destinationAddresses: ['Storage']
            destinationPorts: ['443']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowAzureMonitor'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeVnetAddressPrefix]
            destinationAddresses: ['AzureMonitor']
            destinationPorts: ['443']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowKeyVault'
            ipProtocols: ['TCP']
            sourceAddresses: [spokeVnetAddressPrefix]
            destinationAddresses: ['AzureKeyVault']
            destinationPorts: ['443']
          }
        ]
      }
    ]
  }
}

// Firewall Policy Rule Collection Group

resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: firewallPolicy
  name: 'DefaultApplicationRuleCollectionGroup'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowMicrosoftServices'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AllowMicrosoftEndpoints'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [spokeVnetAddressPrefix]
            targetFqdns: [
              '*.microsoft.com'
              '*.azure.com'
              '*.windows.net'
              '*.microsoftonline.com'
              '*.aadcdn.microsoftonline-p.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AllowDatabricksControlPlane'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            sourceAddresses: [spokeVnetAddressPrefix]
            targetFqdns: [
              '*.azuredatabricks.net'
              '*.databricks.com'
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
  ]
}

// Azure Firewall

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: firewallName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'firewall-ip-config'
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPip.id
          }
        }
      }
    ]
  }
  dependsOn: [
    applicationRuleCollectionGroup
  ]
}

// Outputs

@description('Azure Firewall resource ID')
output firewallId string = firewall.id

@description('Azure Firewall name')
output firewallName string = firewall.name

@description('Azure Firewall private IP address (for UDR configuration)')
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
