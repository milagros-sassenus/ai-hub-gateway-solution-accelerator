# 🏗️ Full Deployment Guide - All Environments

This guide covers deploying the AI Citadel Governance Hub across **development, staging, and production** environments with enterprise-grade configuration, networking, and governance.

For quick non-production deployments, see the [Quick Deployment Guide](./quick-deployment-guide.md).

### How to use this guide

Deploying the hub is a three-phase journey. This guide covers **Phase 1 (Plan)** and **Phase 2 (Deploy)**; day-2 configuration lives in the [Post-Deployment Guide](./post-deployment-guide.md).

| Phase | You do | Primary references |
|-------|--------|--------------------|
| **1. Plan** | Pick region(s), network model, SKUs, resiliency/BC-DR posture | This guide · [Networking Guide](./network-approach.md) · [Sizing Guide](./citadel-sizing-guide.md) · [Resiliency Guide](./resiliency-guide.md) · [BC/DR Guide](./business-continuity-dr-guide.md) |
| **2. Deploy** | Provision the landing zone (`azd up`) | This guide |
| **3. Operate** | Onboard backends & use cases, enable auth, activate reporting, upgrade | [Post-Deployment Guide](./post-deployment-guide.md) |

> 💡 **Complete the [Deployment Decisions Checklist](#-deployment-decisions-checklist) first.** Every decision maps to a parameter in [`main.bicepparam`](../bicep/infra/main.bicepparam), so a completed checklist becomes your deployment configuration.

### Existing VNet and Foundry without reprovisioning them

The initial deployment can use a VNet and private DNS zones prepared separately
(for example, with Azure CLI), while managing dedicated gateway subnets in Bicep:

- Set `useExistingVnet = true`, `existingVnetRG`, and `vnetName`.
- Set `manageExistingVnetSubnets = true` for StandardV2/PremiumV2. Provide names
  and non-overlapping prefixes for APIM, private endpoints, and Logic App subnets.
  The deployment manages these three subnets' properties and an APIM NSG, not
  the parent VNet or its address space. Use new dedicated subnets; do not point
  this option at subnets with externally managed delegations, NSGs or routes.
  Subnet writes are serialized. Existing deployments default to reference-only.
  With `enableUsageReporting = false`, only APIM and private endpoint subnets
  are managed; the Logic App subnet and its dedicated NSG are omitted.
- Create the DNS zones and VNet links before provisioning. Set `dnsZoneRG` and
  optionally `dnsSubscriptionId`, or supply `existingPrivateDnsZones` resource
  IDs. With `useExistingVnet = true`, the deployment does not create DNS zones
  or VNet links. For the standard hub services, prepare
  `privatelink.azure-api.net`, `privatelink.vaultcore.azure.net`,
  `privatelink.servicebus.windows.net`, `privatelink.documents.azure.com`, and
  the `privatelink.blob/file/table/queue.core.windows.net` zones (four zones).
  Additional services require their respective zones.
  With reporting disabled, Event Hubs, Cosmos DB and Storage zones are not
  required and are not created in new-VNet mode.
- Set `existingAiFoundry = { name: '<account>', resourceGroupName: '<rg>' }`.
  An optional `subscriptionId` selects a different subscription; omitting it
  uses the deployment subscription. Set `aiFoundryInstances = []` and
  `aiFoundryModelsConfig = []` to make the intent explicit.
- Supply `existingLlmBackendConfig` using the backend onboarding schema and
  **existing deployment names**. These entries register routing in APIM only.
  No Foundry accounts, projects, model deployments, network settings, private
  endpoints, monitoring connections or Foundry-to-Key-Vault grants are
  provisioned for the existing account. The deployment adds the APIM managed
  identity's Cognitive Services User role at the existing account scope.
  The deployer therefore needs role-assignment permissions there.
- The existing Foundry endpoint is also used for PII/Content Safety. Validate
  these capabilities separately. Its current network access is preserved;
  referencing a public account does not make the backend connection private,
  and deploying the hub in Brazil South does not relocate an East US 2 model.
- For APIM v2 bootstrap, keep `apimV2PublicNetworkAccess = true` while creating
  its private endpoint. After approval, DNS resolution and a private inference
  request have passed, update it to `false` and verify public requests fail.

Use the subscription selected by `az account set`; no login or subscription
switch is performed by these templates. Direct Bicep infrastructure deployment
does not publish the Logic App workflows; publish them separately. Private SCM
publishing requires a connected machine.

### Development without usage ingestion or reporting

The [SFC dev parameters](../bicep/infra/apim-gateway-upgrade/main.parameters.dev.bicepparam)
set `enableUsageReporting = false` and `createAppInsightsDashboards = false`.
The reporting flag defaults to `true` in the initial deployment templates, so
other configurations retain their existing behavior.

Disabled resources include the usage Logic App and hosting plan, its managed
identity/RBAC, Azure Monitor API connection, dedicated Application Insights,
Storage account/file share, Event Hubs namespace/hubs, Cosmos DB account and
containers, and their private endpoints. The usage subnet is not provisioned;
its configured address range is reserved for a later phase.

APIM, Key Vault, Foundry backend routing, PII anonymization/deanonymization, and
basic gateway diagnostics in Application Insights/Log Analytics remain enabled.
Event Hub loggers and their APIM sender role are omitted. The `ai-usage` and
`pii-state-saving` fragments keep their stable names but contain explicitly
disabled bodies, so API policies do not reference missing loggers.
No Cosmos usage/cost history, PII-state audit or scheduled usage aggregation is
available in this mode. Cosmos/Event Hub name outputs are empty by design.

Use the dev parameter file explicitly for the infrastructure deployment.
Do **not** run `azd up` or `azd deploy` for this profile:
[azure.yaml](../azure.yaml) still declares the Logic App service for full
environments and would attempt to publish it. Direct Bicep infrastructure
deployment does not invoke that service. The standalone gateway-upgrade and
supporting-services templates are separate entry points, not controlled by
this initial-deployment flag.

For a later reporting phase, set `enableUsageReporting = true`, prepare the
additional DNS zones/links if using an existing VNet, provision infrastructure,
then publish and validate the Logic App workflows separately. Disabling the
flag is not a deletion mechanism for resources deployed previously.

### Private dev entry through the existing Application Gateway

The SFC dev profile reuses `agw-bancoagrario-lab` in `rg-bancoagrario-lab`
(Brazil South), with private frontend `10.0.0.10` in `vnet-bancoagrario-lab`
(`10.0.0.0/16`). It is a stopped **Standard_v2** gateway, not WAF_v2.
Do not start it, change its SKU, replace its configuration, or alter existing
listeners/routes as part of the hub deployment. WAF and gateway startup need
separate approval; this profile does not yet implement the full WAF architecture.
The existing apps, AKS ingress gateway, Front Door and corporate firewall are
outside this deployment.

#### 1. Prepare the network before deploying the hub

[network-prerequisites.bicep](../bicep/infra/apim-gateway-upgrade/network-prerequisites.bicep)
is a separate subscription-scope entry point. It creates the dev resource group,
the AI Hub VNet (`10.223.2.0/24`), direct peering in both directions, and the APIM
private DNS zone with links to both VNets. It reuses the existing
`privatelink.vaultcore.azure.net` and `bancoagrario.local` zones in the gateway
resource group, adding only links for the new hub VNet. Their current records
and links are preserved. No new Key Vault DNS zone is needed.

The prerequisite template does not deploy subnets, APIM, certificates, Key Vault,
apps, Logic Apps or reporting. The subsequent hub deployment manages its two
dedicated subnets in Bicep. It still creates its own hub Key Vault: reusing the
lab vault for the listener certificate does not replace the hub's secret store.
No existing Application Gateway or parent gateway VNet is redeployed.

Use the same subscription as the dev deployment. Review address ranges, existing
zones, resource ownership and permissions before applying. Peering is not
transitive: apps in other networks need their own approved routing and DNS
resolution. The deployer needs network/DNS write permissions in the laboratory
resource group, resource creation permissions in the hub scope, and permission
to assign the APIM identity's roles on the existing Foundry account and hub.

These are **manual commands for a later approved deployment**, not commands
executed by compilation or tests. From the repository root, review the network
plan first:

```powershell
az deployment sub what-if --name sfc-dev-network --location brazilsouth --template-file .\bicep\infra\apim-gateway-upgrade\network-prerequisites.bicep --parameters resourceGroupName=rg-sfc-ai-landing-zone location=brazilsouth vnetName=vnet-sfc-aihub-dev-brs vnetAddressPrefix=10.223.2.0/24 gatewayResourceGroupName=rg-bancoagrario-lab gatewayVnetName=vnet-bancoagrario-lab internalDnsZoneName=bancoagrario.local
```

Only after explicit approval, execute the same command with `create` instead
of `what-if`. Verify both peerings are `Connected`, DNS links are `Completed`,
and the existing gateway/subnets/listeners were not changed. Inspect the plan
again on reruns; never use complete deployment mode.

Then review and, separately, approve the hub deployment:

```powershell
az deployment sub what-if --name sfc-aihub-dev --location brazilsouth --template-file .\bicep\infra\main.bicep --parameters .\bicep\infra\apim-gateway-upgrade\main.parameters.dev.bicepparam
```

The dev file points `dnsZoneRG` at `rg-bancoagrario-lab`, matching the prerequisite
template. Keep these inputs aligned. A what-if against the hub before its network
prerequisites exist may fail; offline compilation does not validate resource
existence, Azure Policy, quota, RBAC or actual connectivity.

#### 2. Prepare HTTPS without changing existing laboratory routes

Use a **new** internal hostname, `aihub.bancoagrario.local`, rather than the
existing `test.bancoagrario.local`. No public domain purchase is required.
From a machine with private access to `kv-bancoagrario-lab1`, inspect the existing
`agw-test-cert` certificate's SAN, validity, issuer and enabled state. Its name
and listener reference do not prove that it is self-signed or covers AI Hub.
If it does not cover the new hostname, create a separate self-signed dev
certificate with that DNS SAN, server-auth usage and an exportable RSA private
key, stored as a PFX-backed certificate in the same vault. Keep the existing
certificate unchanged. Do not put a PFX, password or private key in the repository.

Do not enable public access on the vault to bypass its current private-only
network restriction. Generating/uploading the certificate requires a connected,
authorized machine. The gateway's existing user-assigned identity must be able
to read the new certificate's secret, with vault network access and a supported
enabled certificate. Verify these permissions; do not assume the current
listener proves access to a different secret. Reference the new certificate
using a versionless Key Vault secret URI.

After separate approval to modify the gateway, add these named objects through
targeted gateway operations or the portal, preserving all existing objects.
Do not deploy a partial `Microsoft.Network/applicationGateways` resource:
its collections represent the full gateway configuration and can overwrite
other laboratory routes. Review existing names and unused rule priorities first.

| New object | Configuration |
|---|---|
| Certificate `aihub-dev-cert` | Verified existing certificate or new Key Vault secret reference |
| Backend pool `aihub-apim` | Actual hub APIM gateway FQDN, `<apim-name>.azure-api.net`, not the AI Hub frontend hostname |
| Probe `aihub-apim-health` | HTTPS, port 443, APIM gateway hostname, `/status-0123456789abcdef`, expect HTTP 200 |
| HTTP settings `aihub-apim-https` | HTTPS 443, Host/SNI set to the APIM gateway hostname, probe above, timeout sized for inference |
| Listener `aihub-private-https` | Existing private frontend `feip-private`, existing HTTPS port 443, host `aihub.bancoagrario.local`, certificate above, SNI enabled |
| Rule `aihub-to-apim` | New unused priority, listener above to pool/settings above; preserve request paths |
| Private DNS A record `aihub` | In `bancoagrario.local`, address `10.0.0.10`; add after the listener is ready |

Use a hostname-specific listener, not a second catch-all listener. The frontend
uses the dev certificate; the APIM backend uses its normal Azure TLS certificate.
Do not upload the dev self-signed certificate as an APIM backend trust anchor.
APIM's FQDN must resolve to its private endpoint from the gateway VNet. Peering
alone does not provide DNS links. Confirm the APIM private endpoint connection
is approved and the gateway can reach it on TCP 443.

#### 3. Validate privately before closing public access

After approval to start the shared gateway (which incurs charges), check backend
health is `Healthy`. From an app/client network with private connectivity and DNS:

1. Resolve `aihub.bancoagrario.local` to `10.0.0.10`.
2. Trust the dev certificate's public certificate/issuer in the client trust
   store. Never disable TLS/hostname validation or use `curl -k`.
3. Call the APIM health path through the new hostname and perform authenticated
   chat and embeddings requests using the actual APIM API routes and subscription
   key. Test PII/Content Safety separately; a deployed model does not prove those
   capabilities work.
4. Confirm the existing `test.bancoagrario.local` listener and routes still work.
5. Only after these checks and approval, set `apimV2PublicNetworkAccess = false`
   in the dev parameter file, review the plan, apply it, then repeat the private
   checks and verify requests over the public gateway endpoint are rejected.

Foundry remains public in East US 2; this network preparation does not make
the APIM-to-Foundry connection private or relocate inference to Brazil South.
Private DNS records/links do not grant clients network access or certificate
trust. Until the connected-machine certificate checks and gateway integration
are complete, this is a prepared deployment path, not a verified live service.

---

## 📋 Table of Contents

1. [Prerequisites](#-prerequisites)
2. [Deployment Decisions Checklist](#-deployment-decisions-checklist)
3. [Deployment Preparation](#-deployment-preparation)
   - [Sizing & SKU Selection](#1-sizing--sku-selection)
   - [Parameter Files Strategy](#2-parameter-files-strategy)
   - [Resource Naming & Tagging](#3-resource-naming--tagging)
   - [Network Architecture](#4-network-architecture)
   - [Resiliency & Business Continuity](#5-resiliency--business-continuity)
   - [AI Model Deployment](#6-ai-model-deployment-optional)
   - [Log Analytics Strategy](#7-log-analytics-strategy)
   - [Inference API Diagnostic Logging](#8-inference-api-diagnostic-logging)
   - [Security & Compliance](#9-security--compliance)
4. [Deployment Execution](#-deployment-execution)
5. [Post-Deployment Validation](#-post-deployment-validation)
6. [Next Steps: Operate the Hub](#-next-steps-operate-the-hub)
7. [Troubleshooting](#-troubleshooting)

---

## ✅ Prerequisites

### Azure Requirements

| Requirement | Details |
|-------------|---------|
| **Azure Subscription** | Active subscription with sufficient quota |
| **Permissions** | Owner or Contributor + User Access Administrator |
| **Resource Providers** | All required providers registered (see below) |
| **Service Quotas** | Verified quotas for LLMs, CosmosDB and other elements |

## 📝 Deployment Decisions Checklist

Work through this checklist first — each decision maps directly to a parameter in [`main.bicepparam`](../bicep/infra/main.bicepparam). The linked guides help you choose.

- [ ] **Sizing (T-shirt size → SKUs)** — pick Small / Medium / Large per environment → [Sizing Guide](./citadel-sizing-guide.md)
  - [ ] Development (cost-optimized SKUs)
  - [ ] Staging (production SKUs, reduced capacity)
  - [ ] Production (production SKUs, full capacity)
- [ ] **Resiliency posture** — circuit breaker, session affinity, failover, error handling → [Resiliency Guide](./resiliency-guide.md)
- [ ] **Business continuity / DR** — single-region, multi-region, or Premium multi-region; RTO/RPO targets → [BC/DR Guide](./business-continuity-dr-guide.md)
- [ ] Subscription allocation
  - [ ] New subscription
  - [ ] Existing subscription
- [ ] Target Azure Region(s)
  - [ ] Primary Region (for core governance components)
  - [ ] Regions for Foundry instances and model deployments
- [ ] Network Approach
  - [ ] Hub-Based (using new subnets in existing hub network)
  - [ ] AIGovSpoke-Hub-Spoke (create dedicated spoke VNet linked to hub)
- [ ] Bring-Your-Own Network
  - [ ] Create new VNet with customized address space
  - [ ] Use existing VNet integration (vnet/subnets already created & configured)
  - [ ] Use exiting Private DNS Zones (better with using existing VNet)
  - [ ] Create new Private DNS Zones (better with new VNet)
- [ ] APIM Network Configuration
  - [ ] External (public endpoint, suitable for dev/test)
  - [ ] Internal (private endpoint, recommended for production)
  - [ ] APIM Custom Domains (list them for gateway, developer portal and management names)
- [ ] Log Analytics Strategy
  - [ ] New Workspace will be created
  - [ ] Use existing centralized Workspace (cross-environment)
- [ ] Resource Naming Convention & tags
  - [ ] Auto-generated names
  - [ ] Custom names/tags per organizational standards
- [ ] Microsoft Foundry Model Deployment
  - [ ] Deploy models as part of AI Citadel deployment (specify models/regions)
  - [ ] None (use existing deployments that will be onboarded later)
- [ ] Inference API Diagnostic Logging
  - [ ] Azure Monitor LLM log verbosity (enabled/disabled, message capture, max payload size)
  - [ ] Application Insights log headers and body capture size
  - [ ] Use defaults (recommended) or customize per environment
- [ ] Source Control Strategy
  - [ ] Single repository with branches per environment
      - [ ] Branch for original unchanged Citadel Governance Hub repo (synchronized with upstream)
      - [ ] Branches for dev, staging, production with environment-specific parameter files (apply changes through new parameter files only)
  - [ ] Separate repositories per environment (with similar branching strategy to point 1)
  - [ ] Automation Strategy
      - [ ] Manual deployments using `azd up` or `az deployment sub create`
      - [ ] CI/CD pipelines (i.e. Azure DevOps or GitHub Actions) for automated deployments

Leverage deployment parameter files ([main.bicepparam](../bicep/infra/main.bicepparam)) to capture these decisions for each environment.

### Required Resource Providers

You can use Azure Cloud Shell or your local Azure CLI installation to register the required resource providers.

First we make sure that the target subscription is selected:

```bash 
az login
az account list --output table
az account set --subscription "<subscription-name or id>"
az account show --output table
```

Then register all required resource providers:

```bash
# Register all required providers
az provider register --namespace Microsoft.AlertsManagement
az provider register --namespace Microsoft.ApiCenter
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Automation
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Diagnostics
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.EventHub
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.MachineLearningServices
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.Monitor
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Resources
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Web

# Verify registration status
az provider list --query "[?registrationState=='Registered'].namespace" -o table
```

### Deployment Tools

**Option 1: Local Machine**
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.50.0+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (v0.20.0+)
- [Git](https://git-scm.com/downloads)
- [VS Code](https://code.visualstudio.com/) with extensions:
  - Bicep

**Option 2: Azure Cloud Shell**
- All tools pre-installed
- Storage account for persistence must be attached
- Built-in editor (in the classic mode)

**Option 3:  DevOps (i.e. Azure DevOps / GitHub Actions)**
- Self-hosted or Microsoft-hosted agents
- Service Principal with appropriate permissions
- Secure variable groups for secrets

---

## 🎯 Deployment Preparation

Based on your choices in the [Deployment Decisions Checklist](#-deployment-decisions-checklist), you can now prepare your deployment configuration.

For source control, make sure you have a working directory linked to your source control repository.

First you need to get the deployment template files:

```bash
# Create a working directory:
mkdir ai-hub-citadel-deployment
# Make the repository your current directory:
cd ai-hub-citadel-deployment # it may differ if you used git clone

# Copy repo files
azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator -e ai-hub-citadel-dev --branch citadel-v1

# or use git clone:
# git clone https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator.git
# git checkout citadel-v1

```

Once you have the Infrastructure-as-Code files, proceed to configure your deployment based on the following strategies.

You can perform the deployment using either `azd up` (recommended) or `az deployment sub create` commands.

### 1. Sizing & SKU Selection

Before touching parameter files, decide the **size** of each environment. The [Citadel Sizing Guide](./citadel-sizing-guide.md) uses a T-shirt model (Small / Medium / Large) tied to expected PTU throughput and SLA needs, and tells you exactly which SKUs to set.

| T-shirt size | Fit | APIM SKU |
|--------------|-----|----------|
| **Small** | Dev / experimental, no SLA | Developer |
| **Medium Classic** | Non-prod or minimum-prod with SLA, full network isolation | Premium |
| **Medium v2** | Non-prod or minimum-prod with SLA | StandardV2 |
| **Large** | Multi-zone production with SLA | Premium (multi-unit) |

Once you have chosen a size, set the SKUs in your parameter file under the **`COMPUTE SKU & SIZE`** block:

```bicep
// ============================================================================
// COMPUTE SKU & SIZE - SKUs and capacity settings for services
// ============================================================================
param apimSku = readEnvironmentVariable('APIM_SKU', 'StandardV2')
param apimSkuUnits = int(readEnvironmentVariable('APIM_SKU_UNITS', '1'))
param eventHubCapacityUnits = int(readEnvironmentVariable('EVENTHUB_CAPACITY', '1'))
param cosmosDbRUs = int(readEnvironmentVariable('COSMOS_DB_RUS', '400'))
param logicAppsSkuCapacityUnits = int(readEnvironmentVariable('LOGIC_APPS_SKU_CAPACITY_UNITS', '1'))
param apicSku = readEnvironmentVariable('APIC_SKU', 'Free')
param keyVaultSkuName = readEnvironmentVariable('KEY_VAULT_SKU_NAME', 'standard')
```

> 📐 **See the [Sizing Guide](./citadel-sizing-guide.md)** for the reference Azure pricing estimates behind each size and for scale-out guidance (adding APIM units).

---

### 2. Parameter Files Strategy

AI Citadel Governance Hub uses **Bicep parameter files (.bicepparam)** for environment-specific configurations.

>NOTE: Always keep a separate copy of your customized parameter files with different names of the main repository `main.bicepparam` to avoid overwriting during updates.

#### Available Parameter Files

| File | Purpose | Use Case |
|------|---------|----------|
| [`main.bicepparam`](../bicep/infra/main.bicepparam) | Environment variables | Used in azd deployments, CI/CD (Default values come from here) |
| [`main.parameters.dev.bicepparam`](../bicep/infra/main.parameters.dev.bicepparam) | Development | Dev/test environments |
| [`main.parameters.prod.bicepparam`](../bicep/infra/main.parameters.prod.bicepparam) | Production | Production workloads |
| [`main.parameters.complete.bicepparam`](../bicep/infra/main.parameters.complete.bicepparam) | Reference | All parameters documented |

#### Parameter File Structure

```bicep
using './main.bicep'

// Basic Configuration
param environmentName = 'citadel-dev'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-dev'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Compute SKUs
param apimSku = 'Developer'
param apimSkuUnits = 1

// Networking
param useExistingVnet = false
param useExistingLogAnalytics = false

// Features
param enableAPICenter = true
```

---

### 3. Resource Naming & Tagging

#### Naming Strategy

AI Citadel supports two naming approaches:

**Option A: Auto-Generated Names (for default non-production deployment)**
```bicep
param resourceGroupName = ''  // Auto-generated: rg-citadel-dev
param apimServiceName = ''    // Auto-generated: apim-abc123def
param logAnalyticsName = ''   // Auto-generated: log-abc123def
```

Benefits:
- ✅ Quick naming across environments
- ✅ Unique names prevent conflicts
- ✅ Includes environment hash for traceability

**Option B: Custom Names**
```bicep
param resourceGroupName = 'rg-ai-gov-citadel-prod-eastus'
param apimServiceName = 'apim-ai-gov-citadel-prod'
param logAnalyticsName = 'law-ai-gov-citadel-shared'
```

Benefits:
- ✅ Human-readable names
- ✅ Matches organizational naming standards
- ✅ Easier to locate in portal

#### Tagging Strategy

**Minimum Required Tags:**
```bicep
param tags = {
  'azd-env-name': 'ai-gov-citadel-prod'
  Environment: 'Production'
  CostCenter: 'Platform'
  Owner: 'platform-team@company.com'
  Criticality: 'High'
}
```

**Recommended Tags by Environment:**

| Tag | Dev | Staging | Production |
|-----|-----|---------|------------|
| Environment | Development | Staging | Production |
| Criticality | Low | Medium | High |
| CostCenter | Engineering | Engineering | Platform |

---

### 4. Network Architecture

#### Network Deployment Approaches

AI Citadel Governance Hub supports **two architectural patterns** for network integration.

Based on your decisions in the earlier checklist, choose one of the following approaches:

##### **Approach 1: Hub-Based (Citadel as Part of Hub)**

Citadel Governance Hub deployed **within** your existing hub VNet.

```
┌─────────────────────────────────────┐
│         Hub Network (VNet)          │
│  ┌──────────────────────────────┐   │
│  │   Citadel Governance Hub     │   │
│  │   - APIM (External/Internal) │   │
│  │   - Private Endpoints        │   │
│  │   - Log Analytics            │   │
│  └──────────────────────────────┘   │
│  ┌──────────────────────────────┐   │
│  │   Shared Services            │   │
│  │   - Azure Firewall & WAF     │   │
│  │   - DNS                      │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
           │           │
           ▼           ▼
    ┌──────────┐  ┌──────────┐
    │ Spoke 1  │  │ Spoke 2  │
    │ Agents   │  │ Agents   │
    └──────────┘  └──────────┘
```

**Configuration:**
```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-eastus'
param existingVnetRG = 'rg-network-hub'
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-private-endpoints'
param functionAppSubnetName = 'snet-citadel-functions'
```

**When to Use:**
- ✅ Citadel manages all enterprise AI traffic
- ✅ Direct spoke-to-hub connectivity
- ✅ Simplified network topology

---

##### **Approach 2: Hub-Spoke-Hub (Citadel as Dedicated Spoke)**

Citadel deployed in a **dedicated spoke** with firewall in between.

```
                 ┌─────────────┐
                 │ Hub Network │
                 │  - Firewall │
                 │  - DNS      │
                 └──────┬──────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
  ┌────────────┐ ┌────────────┐ ┌────────────┐
  │  Spoke 1   │ │  Citadel   │ │  Spoke 2   │
  │  Agents    │ │  Governance│ │  Agents    │
  └────────────┘ │   Hub      │ └────────────┘
                 │  - APIM    │
                 │  - PE      │
                 └────────────┘
```

**Configuration:**
```bicep
param useExistingVnet = false  // Creates new spoke VNet
param vnetName = 'vnet-citadel-eastus'
param vnetAddressPrefix = '10.170.0.0/24'
param dnsZoneRG = 'rg-network-hub'
param dnsSubscriptionId = '<hub-subscription-id>'

// Post-deployment: Configure VNet peering to hub
```

**When to Use:**
- ✅ Defense-in-depth security (dual inspection)
- ✅ Isolated AI workloads from general traffic
- ✅ Separate cost centers/subscriptions
- ✅ Compliance requirements for network isolation

---

#### Network Setup Options

##### **Option 1: Create New Network (Greenfield)**

Citadel creates all networking components:

```bicep
param useExistingVnet = false
param vnetAddressPrefix = '10.170.0.0/24'
param apimSubnetPrefix = '10.170.0.0/26'
param privateEndpointSubnetPrefix = '10.170.0.64/26'
param functionAppSubnetPrefix = '10.170.0.128/26'

// Network access
param apimNetworkType = 'External'  // or 'Internal' for production
param apimV2UsePrivateEndpoint = true
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Enabled'  // Required during deployment of APIM v2 SKUs
```

**Includes:**
- ✅ Virtual Network with subnets
- ✅ Network Security Groups
- ✅ Private DNS Zones
- ✅ Private endpoints according to each service's configuration; the Logic App endpoint is opt-in
- ✅ Route tables (needed for APIM Developer and Premium SKUs)

---

##### **Option 2: Bring Your Own Network (Brownfield)**

Integrate with existing enterprise network:

```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-prod-eastus'
param existingVnetRG = 'rg-network-prod'

// Subnet names (must exist)
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-pe'
param functionAppSubnetName = 'snet-citadel-functions'

// DNS configuration
param dnsZoneRG = 'rg-network-dns'
param dnsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

**Prerequisites:**
1. VNet with sufficient address space
2. Three subnets created:
   - APIM subnet: `/26` or larger (64 IPs)
   - Private endpoint subnet: `/26` or larger
   - Function App subnet: `/26` or larger
3. Private DNS zones created (or delegated)
4. NSG required rules configured for APIM subnet

**Required DNS Zones:**
- `privatelink.azurewebsites.net` when `logicAppUsePrivateEndpoint = true`; supply `existingPrivateDnsZones.logicApp` or reuse the zone through `dnsZoneRG` / `dnsSubscriptionId`, with links or forwarding configured (see [Logic App DNS selection](./network-approach.md#logic-app-private-connectivity)).
- `privatelink.vaultcore.azure.com`
- `privatelink.monitor.azure.com`
- `privatelink.servicebus.windows.net`
- `privatelink.documents.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.file.core.windows.net`
- `privatelink.table.core.windows.net`
- `privatelink.queue.core.windows.net`
- `privatelink.azure-api.net` (for APIM v2 SKUs)
- `privatelink.services.ai.azure.com` (for AI Foundry)
- `privatelink.openai.azure.com` (for AI Foundry)
- `privatelink.cognitiveservices.azure.com` (for AI Foundry)

**APIM Subnet Requirements:**

For **Developer/Premium SKU** (VNet injection):
```bash
# No special delegation required
# NSG must allow all required APIM management traffic
# must have required service endpoints enabled
# associated with APIM route table
```

For **StandardV2/PremiumV2 SKU** (Private Endpoint):
```bash
# Standard subnet configuration
# Private endpoint will be created
```

Detailed guide: [Bring Your Own Network](./network-approach.md)

---

### 5. Resiliency & Business Continuity

Resiliency is a **planning decision**, not a post-deploy afterthought — the topology and SKU you pick here determine what recovery objectives you can meet. Two complementary guides cover the two layers:

| Layer | What it protects | Guide |
|-------|------------------|-------|
| **Backend resiliency** | Keeping LLM traffic flowing when a *backend* throttles or fails — circuit breaking, session affinity, automated failover, structured error handling. | [Resiliency Guide](./resiliency-guide.md) |
| **Hub business continuity** | Keeping the *gateway itself* available when a service, zone, or whole region fails — multi-region topologies, global routing, Cosmos DB multi-write. | [BC/DR Guide](./business-continuity-dr-guide.md) |

> **Golden rule:** a resilient gateway in front of a fragile backend still fails, and a resilient backend behind a single-region gateway is unreachable when that region goes down. **Plan both.**

**Decisions to lock in now (they influence SKU, region, and network choices above):**

- [ ] **BC/DR topology** — single-region + zone redundancy, multiple full deployments (recommended, works on StandardV2+), or APIM Premium multi-region. See [Deployment topologies](./business-continuity-dr-guide.md#3-deployment-topologies).
- [ ] **RTO / RPO / RLO targets** per use case (drives topology). See [Planning your BC/DR strategy](./business-continuity-dr-guide.md#2-planning-your-bcdr-strategy).
- [ ] **Global usage consolidation** — if going multi-region, plan Cosmos DB multi-write via [`citadel-cosmos-global-multi-master-sync`](../bicep/infra/citadel-cosmos-global-multi-master-sync/README.md) (configured post-deployment).

> Circuit breaker, session affinity, and failover defaults are applied automatically during **backend onboarding** (a post-deployment step) — you tune them there. See the [Post-Deployment Guide](./post-deployment-guide.md).

---

### 6. AI Model Deployment (Optional)

#### Microsoft Foundry Configuration

AI Citadel always deploys at least **one Microsoft Foundry resource** — the **primary** Foundry (the first entry in `aiFoundryInstances`). This primary Foundry is mandatory because the AI Citadel Gateway re-uses its **AI Services unified endpoint** (`https://<foundry>.cognitiveservices.azure.com/`) to power:

- **Content Safety** policies (`llm-content-safety` / `content-safety-backend` in APIM)
- **PII detection / anonymization** policies (`piiServiceUrl` named value in APIM)

Additional entries can be added to deploy **extra Foundry resources in different regions** for added LLM capacity, geo-redundancy, or access to region-restricted models. The primary Foundry can also host LLM deployments alongside the additional ones — there is no separation between "core capability" and "LLM" Foundry roles.

> **Note:** The previous standalone Azure Language Service and Azure AI Content Safety resources are no longer provisioned. Their capabilities are consumed directly from the primary Foundry account (AI Services kind), removing two private endpoints and simplifying RBAC and DNS configuration.

Input parameters are separated into two parts:

##### Foundry instances deployment

```bicep
// AI Foundry instances configuration array
param aiFoundryInstances = [
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]
```

The above, creates two Foundry instances in `swedencentral` and `eastus2` regions as examples.

This allows you to deploy models in multiple regions for geo-redundancy, added capacity or accessing restricted regional models.

###### Foundry model deployments

```bicep
// AI Foundry model deployments configuration
param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0 // First instance in aiFoundryInstances array
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4'
    publisher: 'Microsoft'
    version: '3'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 0
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5'
    publisher: 'OpenAI'
    version: '2025-08-07'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 1 // Second instance in aiFoundryInstances array
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 1
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 1
  }
]
```

>NOTE: Ensure that your target subscription has sufficient quota for the selected models.

##### Disable Microsoft Foundry Model deployment

If you are planning to leverage existing model deployments or you are planning to provision the LLMs separately, you can skip model deployment during Citadel provisioning. 

```bicep
param aiFoundryModelsConfig = [] // No models will be deployed as part of AI Citadel primary deployment
```

---

### 7. Log Analytics Strategy

#### Option 1: Create New Log Analytics Workspace

**Recommended for:** Isolated environments, proof-of-concept, dedicated subscriptions

```bicep
param useExistingLogAnalytics = false
param logAnalyticsName = ''  // Auto-generated if empty or supply a compliant name.
```

**Benefits:**
- ✅ Isolated logs per environment
- ✅ Independent retention policies
- ✅ Simplified RBAC
- ✅ Environment-specific dashboards

**Typical Setup:**
```
┌────────────────┐  ┌────────────────┐  ┌─────────────────┐
│ LAW Dev        │  │ LAW Staging    │  │ LAW Prod        │
│ - 30d retention│  │ - 90d retention│  │ - 180d retention│
│ - Dev RBAC     │  │ - Ops RBAC     │  │ - Audit RBAC    │
└────────────────┘  └────────────────┘  └─────────────────┘
```

---

#### Option 2: Bring Your Own Log Analytics (Recommended for Enterprise)

**Recommended for:** Enterprise, multi-environment, centralized monitoring

```bicep
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-centralized-prod'
param existingLogAnalyticsRG = 'rg-monitoring-prod'
param existingLogAnalyticsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

>NOTE: Log Analytics can exists in a different subscription than the Citadel governance hub deployment subscription.

**Benefits:**
- ✅ Centralized logging across all environments
- ✅ Integration with central SIEM
- ✅ Cross-environment correlation
- ✅ Compliance and audit requirements

**Typical Setup:**
```
              ┌──────────────────────────┐
              │ Centralized LAW (Prod)   │
              │ - All environments       │
              │ - 180d retention         │
              │ - Advanced analytics     │
              └──────────────────────────┘
                            ▲
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
    ┌────────┐         ┌────────┐        ┌────────┐
    │  Dev   │         │Staging │        │  Prod  │
    │ Citadel│         │Citadel │        │ Citadel│
    └────────┘         └────────┘        └────────┘
```

---

### 8. Inference API Diagnostic Logging

AI Citadel configures **per-API diagnostic logging** on every inference API (Universal LLM API and Azure OpenAI API). Two diagnostic channels are provisioned:

| Channel | Purpose | Default Destination |
|---------|---------|--------------------|
| **Azure Monitor** (`azuremonitor`) | LLM-aware diagnostics sent to Log Analytics | Azure Monitor / Log Analytics |
| **Application Insights** (`applicationinsights`) | Request/response tracing with custom headers | Application Insights |

Both channels are fully configurable through the deployment parameter files.

#### Azure Monitor Log Settings (`azureMonitorLogSettings`)

Controls frontend/backend request and response header capture, body byte limits, and **LLM-specific** log settings (prompt/completion logging).

**Default values:**

```bicep
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }   // No frontend headers/body captured by default
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }   // No backend headers/body captured by default
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'                                  // LLM logging enabled
    requests:  { messages: 'all', maxSizeInBytes: 262144 }  // Capture all prompt messages (up to 256 KB)
    responses: { messages: 'all', maxSizeInBytes: 262144 }  // Capture all completion messages (up to 256 KB)
  }
}
```

| Property | Default | Description |
|----------|---------|-------------|
| `frontend.request.headers` | `[]` | HTTP headers to capture from the client request |
| `frontend.request.body.bytes` | `0` | Max bytes of client request body to log (`0` = none) |
| `frontend.response.headers` | `[]` | HTTP headers to capture from the response to client |
| `frontend.response.body.bytes` | `0` | Max bytes of response body to log (`0` = none) |
| `backend.request.headers` | `[]` | HTTP headers to capture from the backend request |
| `backend.request.body.bytes` | `0` | Max bytes of backend request body to log (`0` = none) |
| `backend.response.headers` | `[]` | HTTP headers to capture from backend response |
| `backend.response.body.bytes` | `0` | Max bytes of backend response body to log (`0` = none) |
| `largeLanguageModel.logs` | `'enabled'` | Enable or disable LLM-specific logging (`'enabled'` / `'disabled'`) |
| `largeLanguageModel.requests.messages` | `'all'` | Which prompt messages to capture (`'all'` / `'none'`) |
| `largeLanguageModel.requests.maxSizeInBytes` | `262144` | Maximum prompt payload size in bytes (256 KB) |
| `largeLanguageModel.responses.messages` | `'all'` | Which completion messages to capture (`'all'` / `'none'`) |
| `largeLanguageModel.responses.maxSizeInBytes` | `262144` | Maximum completion payload size in bytes (256 KB) |

**Example — Production with header capture and reduced LLM payload:**
```bicep
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [ 'Content-type', 'User-agent' ], body: { bytes: 0 } }
    response: { headers: [ 'x-ms-region' ], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [ 'Content-type' ], body: { bytes: 8192 } }
    response: { headers: [ 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ], body: { bytes: 8192 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 131072 }  // 128 KB limit
    responses: { messages: 'all', maxSizeInBytes: 131072 }
  }
}
```

**Example — Disable LLM prompt/completion logging (privacy-sensitive environments):**
```bicep
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'disabled'
    requests:  { messages: 'none', maxSizeInBytes: 0 }
    responses: { messages: 'none', maxSizeInBytes: 0 }
  }
}
```

---

#### Application Insights Log Settings (`appInsightsLogSettings`)

Controls which HTTP headers are captured and how many bytes of request/response body are logged to Application Insights for all inference APIs.

**Default values:**

```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }  // No body captured by default
}
```

| Property | Default | Description |
|----------|---------|-------------|
| `headers` | `[ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]` | HTTP headers captured in both frontend and backend request/response traces |
| `body.bytes` | `0` | Max bytes of request/response body to log (`0` = none) |

**Example — Capture up to 8 KB of body content:**
```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 8192 }
}
```

**Example — Minimal header capture for cost-sensitive environments:**
```bicep
param appInsightsLogSettings = {
  headers: [ 'Content-type' ]
  body: { bytes: 0 }
}
```

---

#### Recommended Settings by Environment

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| **Azure Monitor LLM logs** | `'enabled'` | `'enabled'` | `'enabled'` (or `'disabled'` for PII-sensitive workloads) |
| **LLM messages capture** | `'all'` | `'all'` | `'all'` or `'none'` |
| **LLM max payload (bytes)** | `262144` (256 KB) | `262144` (256 KB) | `131072`–`262144` (128–256 KB) |
| **App Insights body bytes** | `8192` (8 KB) | `0` | `0` |
| **App Insights headers** | All 5 defaults | All 5 defaults | All 5 defaults |

> **Note:** Increasing body byte capture or LLM payload sizes will increase Log Analytics and Application Insights ingestion costs. For production environments, balance observability needs against cost and data-sensitivity requirements.

---

### 9. Security & Compliance

#### Entra ID Authentication

JWT-based authentication adds a security layer on top of subscription API keys. When enabled, the gateway validates JWT tokens from Microsoft Entra ID before forwarding requests to backends.

**Automatic Provisioning (Recommended):**

Set `entraAuth` to `true` and leave `entraClientId` empty. After deploying the landing zone, run the standalone Entra ID setup script which creates the app registration **and configures APIM directly** — no redeployment needed:

```bash
# 1. Deploy the gateway infrastructure (creates Key Vault, APIM, etc.)
azd up

# 2. Run Entra ID setup (creates app registration + configures APIM named values)
cd bicep/infra/entra-id-setup
pwsh ./setup.ps1

# Done! APIM is now JWT-ready. No redeployment needed.
```

The setup script automatically:
1. Creates an Entra ID App Registration with OAuth2 scopes and app roles
2. Creates a service principal
3. Generates a client secret and stores it in Key Vault as `ENTRA-APP-CLIENT-SECRET`
4. Configures APIM JWT named values directly: `JWT-TenantId`, `JWT-AppRegistrationId`, `JWT-Issuer`, `JWT-OpenIdConfigUrl`
5. Stores `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_AUDIENCE` as azd environment variables for future deployments
6. Prepares direct validation role assignments for a dedicated client service principal
   and signed-in user, an MCP.Invoke-only negative client, and Azure CLI delegated
   preauthorization. The JWT notebook loads these outputs without manual inputs

For additional clients, role definitions do not grant permissions. Assign `Model.Invoke`,
`MCP.Invoke`, and/or `Agent.Invoke` directly to each application's or managed
identity's service principal. Security-group role assignments apply to users,
not service-principal members. See [Client Identity and Permissions](./jwt-client-identity-permissions.md).

> **Prerequisite:** Run as an Azure CLI user with application-management and
> app-role-assignment permissions, for example Cloud Application Administrator.
> Application Developer alone is not enough for the validation assignments.

See [Entra ID Setup README](../bicep/infra/entra-id-setup/README.md) for full details.

```bicep
param entraAuth = true
// Leave these empty for auto-provisioning:
param entraTenantId = ''
param entraClientId = ''
param entraAudience = ''
```

**Manual Configuration (Bring Your Own App Registration):**

```bicep
param entraAuth = true
param entraTenantId = '00000000-0000-0000-0000-000000000000'
param entraClientId = '11111111-2222-3333-4444-555555555555'
param entraAudience = 'api://citadel-gateway'
```

**How JWT Authentication Works Across APIs:**

- JWT named values are deployed when `entraAuth=true`, supporting all APIs (Azure OpenAI, Universal LLM, Unified AI)
- API Key authentication is always required (subscription-based)
- JWT validation is optional per access contract — enable it per product by setting `jwtAuth.enabled: true` in the access contract JSON
- The `security-handler` policy fragment handles both API Key and JWT validation
- When a product requires JWT, clients must send both `api-key` and `Authorization: Bearer {token}` headers

**Access Contract JWT Integration:**

To require JWT authentication for a specific access contract, include the `jwtAuth` policy in the contract JSON:

```json
{
  "policies": {
    "jwtAuth": { "enabled": true },
    "modelAccess": { "enabled": true, "allowedModels": ["gpt-4o"] }
  }
}
```

**Acquiring a JWT Token (Client Credentials Flow):**

```http
POST https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={entra-app-client-id}
&client_secret={entra-app-client-secret}
&scope={audience}/.default
```

**Validation:** See the [JWT Access Contract Validation Notebook](../test/citadel-jwt-access-contract-tests.ipynb) for end-to-end testing.

Guide: [Entra ID Authentication](./entraid-auth-validation.md)

#### Network Security

All applicable network security settings are configurable through the parameters of the accelerator:

**Suggested Production Configuration:**
```bicep
// APIM Security
param apimNetworkType = 'Internal'  // No public access (applies to APIM Developer and Premium SKUs)
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = false

// Service Network Access
param logicAppUsePrivateEndpoint = true
param logicAppPublicNetworkAccess = false
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Disabled'  // Enable during deployment, disable after for APIM Standardv2 and PremiumV2 SKUs

...

```

---

## 🚀 Deployment Execution

It is recommended to leverage Azure Developer CLI (`azd`) for simplified deployments of both the infrastructure and application (Logic Apps workflows).

Based on the configured parameter files, you can deploy using either `az deployment sub create` or `azd up`.

### Private-only Logic App publishing

The Logic App defaults remain `logicAppUsePrivateEndpoint = false` and `logicAppPublicNetworkAccess = true`. To deploy it with private-only website and SCM/Kudu access, use the two overrides in the production example above, or their environment-variable equivalents in the [parameter reference](./parameters-usage-guide.md#logic-app-private-access).

Infrastructure provisioning uses Azure Resource Manager; workflow publishing connects to the app's SCM endpoint. A successful infrastructure deployment does not prove that the publishing machine can reach SCM. Before publishing with public access disabled:

1. Prepare a workstation or self-hosted CI runner in the VNet or a connected network, with routing and HTTPS access to the private endpoint. Ordinary Cloud Shell and public hosted runners should not be assumed to have this access.
2. Configure private DNS links or forwarding so both `<app>.azurewebsites.net` and `<app>.scm.azurewebsites.net` resolve to the private endpoint IP from that machine. For an existing VNet, supply the existing zone ID or `dnsZoneRG`; see [DNS selection and ownership](./network-approach.md#logic-app-private-connectivity).
3. Confirm endpoint approval and private DNS/connectivity after provisioning, then publish workflows from that connected machine using the required deployment credentials and permissions. Private networking does not bypass authentication.

For `azd up`, the application deployment phase runs from the machine invoking it, which therefore needs private SCM access. When using separate provisioning and application deployment steps, run the publishing step from the connected machine. This prerequisite also applies to separate workflow publishing after a direct Bicep deployment, including the existing-resource-group path below.

A new deployment can start private-only; temporarily enabling public access is not required when the private publishing path is ready. Setting both flags to `true` is an optional staged-verification mode only when policy permits. It is not an instruction to rerun the full accelerator against an existing hub.

The main and resource-group templates are for initial deployment. Converting an existing app requires a separately reviewed, narrowly scoped maintenance change; these flags are not added to the gateway-upgrade supporting-services templates. Network changes may restart an existing app or delay ingestion. Do not change other services' access settings just to publish the Logic App. See [post-deployment private connectivity checks](./post-deployment-guide.md#logic-app-private-connectivity-checks).

### Using `az deployment sub create`:

**For Development:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.dev.bicepparam
```

**For Production:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.prod.bicepparam
```

**For Custom Environments:**
1. Copy `main.parameters.complete.bicepparam`
2. Rename to `main.parameters.<env>.bicepparam`
3. Customize values
4. Version control the file

>Note: Using `az deployment sub create` will only provision the infrastructure. You still will need to deploy the `Logic App` workflows separately after the infrastructure is ready.

> With Logic App public access disabled, that separate workflow publishing step requires [private SCM connectivity](#private-only-logic-app-publishing).

### Using `azd up`:

This automatically picks up the `main.bicepparam` file. You can override specific parameters using environment variables or by modifying the `main.bicepparam` file directly.

```bash
# Authenticate to Azure
# append --tenant-id <your-tenant-id> if needed
azd auth login

# Initialize environment
azd env new ai-hub-citadel-dev-01

# Provision and deploy everything based on defaults
azd up
```

>NOTE: Using `azd up` will use the `main.bicepparam` file for parameter values. You can modify it or set environment variables to override specific parameters. This command provisions the infrastructure and deploys the Logic App workflows in one step.

> With Logic App public access disabled, run this command from a machine that meets the [private publishing prerequisites](#private-only-logic-app-publishing).

### Existing Resource Group Deployment Execution

Use this path only when subscription-scoped deployment is not possible and the hub resource group already exists. Create your own resource-scope parameter file, such as `resources.parameters.dev.bicepparam` or `resources.parameters.prod.bicepparam`, with the values for that environment. This exception uses `resources.bicep` directly at resource group scope. It is not an `azd up` flow.

Replace `dev` in the example below with your environment name when needed.

```bash
# Preview the resource-group deployment
az deployment group what-if \
  --resource-group <existing-hub-resource-group> \
  --template-file ./bicep/infra/resources.bicep \
  --parameters ./bicep/infra/resources.parameters.dev.bicepparam

# Deploy infrastructure into the existing resource group
az deployment group create \
  --resource-group <existing-hub-resource-group> \
  --template-file ./bicep/infra/resources.bicep \
  --parameters ./bicep/infra/resources.parameters.dev.bicepparam
```

---

## ✅ Post-Deployment Validation

Confirm the landing zone provisioned correctly before moving on to configuration.

### Verify Resource Deployment

```bash
# List all resources in resource group
RG_NAME=$(az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.resourceGroupName.value -o tsv)

az resource list \
  --resource-group $RG_NAME \
  --output table

```

### Validate Governance Hub functionality

This repo includes a set of validation notebooks under the `/validation` folder:

- [llm-backend-onboarding-runner.ipynb](../validation/llm-backend-onboarding-runner.ipynb): Onboard existing LLM backends, configure routing, and validate connectivity.
- [citadel-access-contracts-tests.ipynb](../validation/citadel-access-contracts-tests.ipynb): Onbaord AI Agents and AI use cases into the gateway
- [citadel-agent-frameworks-tests.ipynb](../validation/citadel-agent-frameworks-tests.ipynb): Build/deploy 3 types of agents that uses the gateway's access contracts (Microsoft Agent Framework, Foundry Agent and LangChain agent)

---

## ➡️ Next Steps: Operate the Hub

The `main.bicep` deployment is the **initial implementation only**. All day-2 configuration — onboarding backends and use cases, enabling authentication, activating usage reporting, going multi-region, and upgrading the gateway to newer releases — is covered end-to-end in the:

### 👉 [Post-Deployment Guide](./post-deployment-guide.md)

At a glance, your next activities are:

| Activity | Guide / Module |
|----------|----------------|
| Onboard LLM backends & routing (**Backend Contract**) | [llm-backend-onboarding](../bicep/infra/llm-backend-onboarding/README.md) · [LLM Access Guide](./llm-access-guide.md) |
| Onboard use cases (**Access Contract**) | [citadel-access-contracts](../bicep/infra/citadel-access-contracts/README.md) |
| Enable Entra ID (JWT) authentication | [entra-id-setup](../bicep/infra/entra-id-setup/README.md) · [Entra ID Auth](./entraid-auth-validation.md) |
| Activate Power BI usage reporting | [Power BI Dashboard](./power-bi-dashboard.md) |
| Go multi-region (Cosmos DB multi-write) | [citadel-cosmos-global-multi-master-sync](../bicep/infra/citadel-cosmos-global-multi-master-sync/README.md) · [BC/DR Guide](./business-continuity-dr-guide.md) |
| Upgrade an existing gateway to a newer release | [APIM Gateway Upgrade](../bicep/infra/apim-gateway-upgrade/README.md) · [Release Version Management](./release-version-management.md) |
| Enable PII detection / masking | [PII Masking](./pii-masking-apim.md) |
| Configure alerts & throttling events | [Throttling Events Handling](./throttling-events-handling.md) |

> **Keeping the repo current:** synchronize your local repository's `original` branch with the upstream accelerator, then open a Pull Request into your environment-specific branch to merge changes. To apply those changes to a *running* gateway, use the [APIM Gateway Upgrade](../bicep/infra/apim-gateway-upgrade/README.md) submodule rather than re-running `main.bicep` — see the [Post-Deployment Guide](./post-deployment-guide.md#6-upgrade-the-gateway-to-a-newer-release).

---

## 🚨 Troubleshooting

Visit the [Deployment Troubleshooting Guide](./#) for common issues and resolutions.

### Getting Help

- **GitHub Issues:** [Report a bug](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/issues)

---

**Congratulations! Your AI Citadel Governance Hub landing zone is deployed. Continue with the [Post-Deployment Guide](./post-deployment-guide.md) to onboard workloads and go live.** 🎉
