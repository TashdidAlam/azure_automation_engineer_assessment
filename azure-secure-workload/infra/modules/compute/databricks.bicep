// Azure Databricks Workspace

@description('Azure region for resource deployment')
param location string

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Resource tags for governance and cost tracking')
param tags object

@description('Databricks workspace pricing tier (standard or premium)')
@allowed(['standard', 'premium'])
param databricksSku string

@description('Resource ID of the Spoke VNet for VNet injection')
param spokeVnetId string

@description('Name of the Databricks host (public) subnet')
param databricksHostSubnetName string

@description('Name of the Databricks container (private) subnet')
param databricksContainerSubnetName string

// Variables

var databricksName = 'dbw-secure-workload-${environmentName}'
var managedRgName = 'rg-databricks-managed-${environmentName}-${uniqueString(resourceGroup().id)}'

// Azure Databricks Workspace - VNet Injection + NPIP

resource databricks 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: databricksName
  location: location
  tags: tags
  sku: {
    name: databricksSku
  }
  properties: {
    managedResourceGroupId: '${subscription().id}/resourceGroups/${managedRgName}'
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules'

    parameters: {
      customVirtualNetworkId: {
        value: spokeVnetId
      }
      customPublicSubnetName: {
        value: databricksHostSubnetName
      }
      customPrivateSubnetName: {
        value: databricksContainerSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
}

// Outputs

@description('Databricks workspace resource ID (for Private Endpoint creation)')
output databricksId string = databricks.id

@description('Databricks workspace name')
output databricksName string = databricks.name

@description('Databricks workspace URL')
output databricksWorkspaceUrl string = databricks.properties.workspaceUrl
