// RBAC Role Assignment

@description('Principal ID of the Managed Identity to grant access')
param principalId string

@description('Built-in role definition GUID (e.g., b24988ac-6180-42a0-ab88-20f7382dd24c for Contributor)')
param roleDefinitionId string

@description('Principal type for the assignment')
@allowed(['ServicePrincipal', 'Group', 'User'])
param principalType string = 'ServicePrincipal'

@description('Description of the role assignment for audit trail')
param roleAssignmentDescription string = ''

// Role Assignment

var roleAssignmentName = guid(resourceGroup().id, principalId, roleDefinitionId)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
    description: !empty(roleAssignmentDescription) ? roleAssignmentDescription : null
  }
}

// Outputs

@description('Role assignment resource ID')
output roleAssignmentId string = roleAssignment.id

@description('Role assignment name (GUID)')
output roleAssignmentName string = roleAssignment.name
