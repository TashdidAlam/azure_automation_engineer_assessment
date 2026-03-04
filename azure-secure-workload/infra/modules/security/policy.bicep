// Azure Policy Assignments

@description('Environment identifier')
@allowed(['dev', 'stg', 'prod'])
param environmentName string

@description('Azure region for assignment metadata')
param location string

var sqlDenyPublicAccessPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/1b8ca024-1d5c-4dec-8995-b1a932b41780'
var appServiceDenyPublicAccessPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/1b5ef780-c53c-4a64-87f3-bb9c8c8094ba'
var adfPrivateLinkPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/8b0323be-cc25-4b61-935d-002c3798c6ea'
var privateEndpointAuditPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/6edd7eda-6dd8-40f7-810d-67160c639cd9'

// Policy Assignment: Deny SQL Public Network Access

resource sqlPublicAccessPolicy 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'deny-sql-public-${environmentName}'
  location: location
  properties: {
    policyDefinitionId: sqlDenyPublicAccessPolicyId
    displayName: 'Deny SQL Public Network Access [${toUpper(environmentName)}]'
    description: 'Prevents Azure SQL Servers from having public network access enabled.'
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'Azure SQL Servers must have public network access disabled. Use Private Endpoints for connectivity.'
      }
    ]
  }
}

// Policy Assignment: Deny App Service Public Network Access

resource appServicePublicAccessPolicy 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'deny-app-public-${environmentName}'
  location: location
  properties: {
    policyDefinitionId: appServiceDenyPublicAccessPolicyId
    displayName: 'Deny App Service Public Network Access [${toUpper(environmentName)}]'
    description: 'Prevents App Service apps from having public network access enabled.'
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'App Service apps must have public network access disabled. Use Private Endpoints for connectivity.'
      }
    ]
  }
}

// Policy Assignment: Require Data Factory Private Link

resource adfPrivateLinkPolicy 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'deny-adf-public-${environmentName}'
  location: location
  properties: {
    policyDefinitionId: adfPrivateLinkPolicyId
    displayName: 'Require ADF Private Link [${toUpper(environmentName)}]'
    description: 'Azure Data Factory instances should use private link for secure connectivity.'
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'Azure Data Factory must use private link. Configure a Private Endpoint for the Data Factory instance.'
      }
    ]
  }
}

// Policy Assignment: Audit Private Endpoint Configuration

resource privateEndpointAuditPolicy 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'audit-pe-config-${environmentName}'
  location: location
  properties: {
    policyDefinitionId: privateEndpointAuditPolicyId
    displayName: 'Audit Private Endpoint Configuration [${toUpper(environmentName)}]'
    description: 'Audits whether resources that support Private Endpoints have them configured.'
    enforcementMode: 'Default'
  }
}

@description('SQL public access policy assignment ID')
output sqlPolicyAssignmentId string = sqlPublicAccessPolicy.id

@description('App Service public access policy assignment ID')
output appServicePolicyAssignmentId string = appServicePublicAccessPolicy.id

@description('Data Factory private link policy assignment ID')
output adfPolicyAssignmentId string = adfPrivateLinkPolicy.id
