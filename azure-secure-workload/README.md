# Azure Secure Workload

This project deploys a Hub-Spoke Azure workload using Bicep. All services communicate privately through Private Endpoints. No public endpoints are exposed. The infrastructure is deployed through an Azure DevOps multi-stage YAML pipeline.

## What Gets Deployed

The Hub VNet holds shared services: Azure Bastion (for secure VM access), Azure Firewall (for egress filtering), and Private DNS Zones (for name resolution). The Spoke VNet holds the application workload: App Service, Azure SQL, Data Factory, and Databricks.

```
+--------------------------------------------------+
|                    HUB VNET                       |
|                                                   |
|   +------------+  +------------+  +------------+  |
|   |  Bastion   |  |  Firewall  |  |  DNS Zones |  |
|   +------------+  +------------+  +------------+  |
+----------+----------------------------------------+
           |
    VNet Peering
           |
+----------+----------------------------------------+
|                   SPOKE VNET                      |
|                                                   |
|   +------------+  +------------+  +------------+  |
|   |App Service |  | Azure SQL  |  |   ADF      |  |
|   +------------+  +------------+  +------------+  |
|                                                   |
|   +------------+  +----------------------------+  |
|   | Databricks |  | Private Endpoints Subnet   |  |
|   +------------+  +----------------------------+  |
+---------------------------------------------------+
```

Each environment (DEV, STG, PROD) gets its own non-overlapping address space so they can be peered or migrated to separate subscriptions later. Specific values are in the parameter files.

## Repository Structure

```
azure-secure-workload/
  infra/
    main.bicep                        Orchestrator
    parameters/
      dev.bicepparam                  DEV environment values
      stg.bicepparam                  STG environment values
      prod.bicepparam                 PROD environment values
    modules/
      networking/                     Hub VNet, Spoke VNet, Peering, DNS, Bastion, Firewall
      compute/                        App Service, Databricks
      data/                           SQL Server, Data Factory
      identity/                       RBAC role assignment module
      security/                       Private Endpoint module, Policy assignments
  pipelines/
    azure-pipelines.yml               Multi-stage CI/CD pipeline
  scripts/
    post-deployment.ps1               Security posture validation
    Migrate-RbacAssignments.ps1       RBAC migration tool (Part 3)
  docs/
    task-1.1-architecture-design.md
    task-1.2-network-security-controls.md
    task-1.3-bicep-deployment.md
    task-1.4-identity-access.md
    task-2-pipeline-design.md
    task-3-rbac-migration.md
    task-4-security-governance.md
```

## How the Pipeline Works

The pipeline triggers on pushes to dev, stg, prod, and feature branches. It only runs when files change under `infra/`, `pipelines/`, or `scripts/`.

Every push goes through validation first: Bicep build, lint, and a What-If preview. Feature branches (dev-*) stop here and never deploy.

For environment branches, the pipeline deploys and then runs post-deployment validation:
- **dev branch** deploys to DEV automatically
- **stg branch** deploys to STG after approval
- **prod branch** deploys to PROD after manual approval, with an extra What-If preview

After each deployment, a PowerShell script checks that public access is disabled on all services, Private Endpoints are connected, Managed Identities are enabled, and DNS zones are properly linked.

## Prerequisites

- Azure subscription with Contributor access
- Azure DevOps project with a service connection to the subscription
- Self-hosted agent (or Microsoft-hosted with a parallel grant)
- Azure CLI with Bicep installed on the agent

## Quick Start

```bash
# Clone the repo
git clone <repo-url>
cd azure-secure-workload

# Build and lint locally
az bicep build --file infra/main.bicep
az bicep lint --file infra/main.bicep

# Preview changes (dry run)
az deployment group what-if \
  --resource-group rg-secure-workload-dev \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# Deploy
az deployment group create \
  --resource-group rg-secure-workload-dev \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam \
  --mode Incremental
```

## Documentation

Each assessment task has a matching document in the `docs/` folder:

| Document | Covers |
|----------|--------|
| task-1.1-architecture-design.md | VNet/subnet design, private connectivity, DNS zones, authentication |
| task-1.2-network-security-controls.md | Service-level security settings, NSGs, firewall, policies |
| task-1.3-bicep-deployment.md | Module breakdown, deployment order, conditional flags |
| task-1.4-identity-access.md | Managed Identities, RBAC assignments, least-privilege |
| task-2-pipeline-design.md | Pipeline stages, environment handling, YAML walkthrough |
| task-3-rbac-migration.md | Migration strategy, PowerShell script, risks, testing guide |
| task-4-security-governance.md | Policy enforcement, failure scenarios, rollback |
