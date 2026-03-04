# Task 1.4 -- Identity and Access (Workload Level)

## Which Services Use System Assigned Managed Identity

| Service | Managed Identity | How It Is Used |
|---------|-----------------|----------------|
| App Service | System Assigned | Authenticates to Azure SQL using a token (no connection string) |
| Data Factory | System Assigned | Authenticates to SQL and other data sources for pipeline orchestration |
| SQL Server | System Assigned | Supports Entra authentication on the server side |
| Databricks | Workspace MI | Workspace-level identity for Entra integration |

Managed Identities are created automatically when the resource is deployed with `identity: { type: 'SystemAssigned' }` in Bicep. The lifecycle is tied to the resource itself -- if the resource is deleted, the identity is cleaned up automatically.

## Which Services Require RBAC Assignments

| Principal (Managed Identity) | Role Assigned | Scope | Why |
|------------------------------|---------------|-------|-----|
| App Service MI | SQL DB Contributor | Resource Group | App needs read/write access to the SQL database |
| Data Factory MI | Data Factory Contributor | Resource Group | ADF needs to manage its own pipelines and triggers |
| Data Factory MI | SQL DB Contributor | Resource Group | ADF data pipelines need to query and write to SQL |

These are assigned through the `rbac.bicep` module using deterministic GUIDs, so re-deploying the same template does not create duplicates.

## Minimum Permissions for Each Service Interaction

**App Service to SQL**: SQL DB Contributor grants data-plane read/write on databases. It does not grant server-level admin or the ability to create/delete databases.

**Data Factory to SQL**: SQL DB Contributor (same as above). ADF uses this to run queries and load data.

**Data Factory self-management**: Data Factory Contributor allows ADF to create and manage pipelines, datasets, and linked services within its own instance.

**Pipeline service principal**: The Azure DevOps service connection has Contributor and User Access Administrator roles scoped to each environment's Resource Group. Contributor lets it create and modify resources. User Access Administrator lets it deploy RBAC role assignments for Managed Identities (`deployRbac = true`). UAA is scoped to the RG, not the subscription, so the service principal cannot grant access to resources outside the target RG. In an enterprise setup, UAA would be scoped at Management Group level and role assignments would target individual resources rather than the Resource Group.

## Authentication Approach

There are no passwords, secrets, or connection strings anywhere in the codebase. Every service-to-service call uses Managed Identity tokens issued by Entra ID.

SQL Server is configured with `azureADOnlyAuthentication: true`, which completely disables SQL username/password authentication. The only way to access SQL is through Entra ID credentials (either a user, group, or managed identity).

In a production environment, I would scope RBAC assignments to individual resources instead of the Resource Group to further tighten permissions. I would also consider using Entra ID Groups for role assignments instead of individual identities, since group membership is easier to audit and survives resource recreation.
