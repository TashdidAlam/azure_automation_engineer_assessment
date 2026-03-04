# Task 4 Security and Governance (Design Only)

## Task 4.1 -- Preventing Public Exposure at Scale

### No Public Endpoints

Every PaaS resource in this workload has `publicNetworkAccess: Disabled` set in its Bicep template. This covers App Service, Azure SQL, Data Factory, and Databricks.

To enforce this beyond a single workload, use Azure Policy with Deny effect. Assign built-in policies that block the creation or modification of any resource that has public network access enabled. This workload assigns four such policies at the Resource Group scope:

| Policy | Effect |
|--------|--------|
| Deny SQL Public Network Access | Deny |
| Deny App Service Public Access | Deny |
| Require ADF Private Link | Deny |
| Audit Private Endpoint Configuration | Audit |


### Mandatory Private Endpoints

Private Endpoints in this workload are deployed using a reusable Bicep module. Each PE is placed in a dedicated subnet, linked to a centralized Private DNS Zone for automatic A-record registration, and validated after deployment by checking the connection state.

At scale, enforce mandatory PE creation through:
- Deny policies that block resource creation without an associated PE
- DeployIfNotExists policies that automatically create PEs when a resource is deployed
- Audit policies that flag resources lacking PE configuration for remediation

### Standard RBAC Role Usage

This workload assigns three RBAC roles, all using least-privilege built-in definitions (SQL DB Contributor, Data Factory Contributor). No custom roles are used for the workload itself.

At enterprise scale:
- Scope RBAC to individual resources rather than resource groups
- Use Privileged Identity Management (PIM) for just-in-time access
- Assign custom roles when built-in roles grant more permissions than needed
- Audit role assignments through Entra ID Access Reviews
- Deny role assignments that use Owner or overly-broad custom roles at subscription scope via Azure Policy

### CI/CD Enforcement

The pipeline enforces security at build time and deploy time:

1. Bicep Lint catches security anti-patterns before deployment
2. What-If previews all changes so the team can verify no public endpoints are being created
3. Post-deployment validation checks every deployed resource for correct security posture
4. STG and PROD deployments require manual approval through Azure DevOps Environment checks before any resources are modified
5. PROD gets an additional What-If preview immediately before deployment for final change review
6. Feature branches only run validation and never deploy, so untested code cannot reach production

The pipeline service principal has Contributor and User Access Administrator roles scoped to each environment's Resource Group. This lets it create resources and assign RBAC roles to Managed Identities (`deployRbac = true`). User Access Administrator is scoped to the RG level, not the subscription, which limits the blast radius -- the service principal cannot grant access to resources outside its target RG.

### Enterprise Improvements Beyond Current Scope

The following capabilities are not implemented due to subscription and budget constraints but would be added in an enterprise deployment:

- **Application Insights APM**: Distributed tracing and live metrics for App Service (current deployment sends platform logs to Log Analytics but does not instrument the application code)
- **Azure Monitor alert rules and dashboards**: Automated alerting on failure thresholds and operational dashboards (Log Analytics workspace is deployed but no alert rules are defined yet)
- **Azure Key Vault**: Certificate management and secret rotation (even though current workload uses only Managed Identities)
- **DDoS Protection Standard**: Applied to the Hub VNet to protect public-facing IPs (Bastion, Firewall)
- **Azure Front Door or Application Gateway with WAF**: Layer 7 protection and global load balancing
- **Multi-region deployment**: Active-passive failover with Traffic Manager or Front Door
- **Geo-redundant SQL backups**: Currently using Local redundancy due to S1 SKU constraints
- **Premium SKUs**: P1v3+ App Service for autoscale and deployment slots, Business Critical SQL for zone redundancy

## Task 4.2 -- Failure Scenarios

### Private Endpoint DNS Misconfiguration

**What happens:** Services deploy successfully but cannot communicate. The app returns 504 or DNS resolution errors when connecting to SQL. The Private Endpoint shows Approved but traffic does not route correctly.

**Common causes:**
- Private DNS Zone is not linked to the VNet where the client resides
- No A-record exists in the zone (DNS zone group was not configured on the PE)
- Multiple conflicting DNS zones exist in different resource groups
- A custom DNS server on the VNet does not forward to Azure DNS (168.63.129.16)

**How to fix it:**

Start by checking DNS resolution from inside the VNet. If `nslookup <service>.database.windows.net` resolves to a public IP, the Private DNS Zone link is missing or forwarding is broken.

Next, check the DNS zone has the correct A-record using `az network private-dns record-set a list`. Then verify VNet links on the zone -- both Hub and Spoke must be linked. If either is missing, DNS resolution fails for clients in that VNet.

Finally, check for duplicate zones. If the same zone name exists in multiple resource groups, the VNet link determines which one wins.

**How this workload prevents it:** DNS zone groups are deployed on every PE, which auto-registers A-records. VNet links are created for both Hub and Spoke in the same Bicep deployment. The post-deployment script validates that all four DNS zones have two VNet links each.

### Partial Pipeline Failure

**What happens:** Deployment fails midway. VNets and SQL deploy successfully, but Private Endpoints fail because DNS zones did not provision in time.

**How to fix it:** Re-run the pipeline. Bicep deployments are idempotent with incremental mode. ARM compares the desired state against the actual state. Resources that already exist are left alone, and only the failed ones are retried.

If the same error repeats, check the ARM deployment operations for the specific error message. Common root causes are quota limits, regional restrictions, missing permissions, or a dependency that failed silently.

**How to roll back:** If a bad template was deployed, revert the git commit and re-run the pipeline. The previous template redeploys the known-good state. For most cases, re-running the same pipeline is sufficient since Bicep deployments are idempotent.

### RBAC Assignment Failure During Migration

**What happens:** When migrating between subscriptions or restructuring Management Groups, Managed Identity principal IDs change because new resources get new identities. Existing RBAC assignments reference the old principal IDs and fail.

**How to fix it:** For workload-level RBAC (App Service, Data Factory identities), clean up orphaned assignments (those with empty principal names in `az role assignment list`) and re-run the Bicep deployment. The `rbac.bicep` module generates deterministic assignment names from the new principal IDs, so it creates fresh assignments automatically.

For Management Group-level RBAC migrations, use the automation script at `scripts/Migrate-RbacAssignments.ps1` (documented in the [Task 3 RBAC Migration doc](task-3-rbac-migration.md)). The script discovers all direct assignments at the source MG, exports them to CSV, validates principals in Entra ID, and reapplies them at the target MG. It handles custom roles, ABAC conditions, orphaned principals, and duplicate detection. Run with `-WhatIf` first for a dry run.

If the service principal loses User Access Administrator permission, set `deployRbac = false` in the affected parameter file. Existing role assignments are not deleted -- they remain in place until manually removed. The rest of the deployment continues normally.

**How to prevent it:** Use deterministic GUID names for role assignments (already implemented in `rbac.bicep`). Separate RBAC deployment behind a feature flag. In enterprise environments, use Entra ID Groups instead of individual managed identities for role assignments. Group membership survives resource recreation.
