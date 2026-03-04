# Task 2 CI/CD Pipeline Design and YAML

## Pipeline Design (Task 2.1)

The pipeline follows a Validate, then Deploy, then Verify pattern. Each environment gets its own stage, and code is promoted through branches (dev to staging to production).

### Stage Separation

**Validate stage** runs on every push, including feature branches (dev-*). It compiles the Bicep template, lints it against best practices, creates the target resource group if needed, and runs a What-If preview. No resources are deployed. This is the build step.

**Deploy stages** run only on their matching branch. DEV deploys automatically on merge to dev. STG and PROD require manual approval before deployment begins -- approval checks are configured on the Azure DevOps Environments (`secure-workload-stg` and `secure-workload-prod`) under Pipelines > Environments > Approvals and checks. PROD also runs an additional What-If preview before deploying. After each deployment, a post-deployment PowerShell script checks the security posture of the deployed resources.

### Environment Handling

Each environment maps to a branch and a parameter file:

| Branch | Environment | Parameter File | Deploy Behavior |
|--------|-------------|---------------|----------|
| dev-* | None (validate only) | dev.bicepparam | Validate only |
| dev | DEV | dev.bicepparam | Auto-deploy |
| staging | STG | stg.bicepparam | Requires approval |
| production | PROD | prod.bicepparam | Requires approval (with extra What-If preview) |

The Bicep template is identical across all environments. Only the parameter values change (region, SKUs, tags, feature flags).

### Secret Management

There are no application secrets in this workload. All service-to-service authentication uses Managed Identities.

For the pipeline itself, the Azure DevOps Service Connection stores the service principal credentials. This is configured in Azure DevOps Project Settings and referenced by name in the YAML. The service principal has Contributor role scoped to the target Resource Group.

Sensitive values like the Entra admin object ID are stored in the parameter files. These are not secrets (they are GUIDs that map to Entra identities), but in a more sensitive setup, they could be moved to Azure DevOps variable groups or Key Vault-linked variables.

### Post-Deployment Validation

After each deployment, the pipeline runs `post-deployment.ps1`, which checks:

1. Resource group exists and has the expected resources
2. SQL Server has public access disabled and Entra admin configured
3. App Service has public access disabled and Managed Identity enabled
4. All Private Endpoints are in Approved state
5. VNet Peering is Connected in both directions
6. Data Factory has public access disabled and Managed Identity enabled
7. Private DNS Zones are linked to both VNets

In DEV, validation failures are logged as warnings. In STG and PROD, any failure stops the pipeline.

## YAML Pipeline (Task 2.2)

The full pipeline YAML is at `pipelines/azure-pipelines.yml`. Here is a summary of what it does:

### Trigger Configuration

The pipeline triggers on pushes to dev, staging, production, and dev-* branches, but only when files change under `infra/`, `pipelines/`, or `scripts/`. Changes to docs or the README do not trigger a build.

PR validation runs on dev, staging, and production branches with the same path filter.

### Variables

The pipeline sets a few variables at the top:
- The Azure service connection name
- The Bicep template path and parameter file path (selected based on branch)
- The resource group name (derived from the environment)
- Deployment location

### Validate Stage

```yaml
- task: AzureCLI@2
  displayName: 'Bicep Build'
  inputs:
    azureSubscription: $(serviceConnection)
    scriptType: pscore
    scriptLocation: inlineScript
    inlineScript: |
      az bicep build --file $(templateFile)

- task: AzureCLI@2
  displayName: 'Bicep Lint'
  inputs:
    azureSubscription: $(serviceConnection)
    scriptType: pscore
    scriptLocation: inlineScript
    inlineScript: |
      az bicep lint --file $(templateFile)

- task: AzureCLI@2
  displayName: 'What-If Preview'
  inputs:
    azureSubscription: $(serviceConnection)
    scriptType: pscore
    scriptLocation: inlineScript
    inlineScript: |
      az deployment group what-if \
        --resource-group $(resourceGroup) \
        --template-file $(templateFile) \
        --parameters $(parameterFile)
```

### Deploy Stage

```yaml
- task: AzureCLI@2
  displayName: 'Deploy Bicep'
  inputs:
    azureSubscription: $(serviceConnection)
    scriptType: pscore
    scriptLocation: inlineScript
    inlineScript: |
      az deployment group create \
        --resource-group $(resourceGroup) \
        --template-file $(templateFile) \
        --parameters $(parameterFile) \
        --mode Incremental

- task: AzurePowerShell@5
  displayName: 'Post-Deployment Validation'
  inputs:
    azureSubscription: $(serviceConnection)
    scriptType: filePath
    scriptPath: scripts/post-deployment.ps1
    scriptArguments: >
      -ResourceGroupName $(resourceGroup)
      -EnvironmentName $(environmentName)
```

### Rollback Approach

The pipeline uses incremental deployment mode, which only applies changes and never deletes resources that are not in the template. If a bad change is deployed, the fix is to revert the git commit and re-run the pipeline, which redeploys the last known good state.

For PROD, the extra What-If preview before deployment gives the team a chance to catch unexpected changes before they go live.
