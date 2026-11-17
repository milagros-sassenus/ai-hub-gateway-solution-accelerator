using '../main.bicep'

// Initial subscription-scoped deployment, not an APIM gateway upgrade.
// Subscription selection comes from Azure CLI; no subscription ID is pinned here.

// ============================================================================
// BASIC PARAMETERS
// ============================================================================
param environmentName = 'rg-sfc-ia-eu-prod'
param location = 'eu'
param apicLocation = 'eu'
param resourceGroupName = 'rg-sfc-ia-eu-prod'
param tags = {
  Environment: 'Development'
  Workload: 'AI Hub'
}

// ============================================================================
// RESOURCE NAMES
// ============================================================================
param logAnalyticsName = 'law-sfc-ia-eu-prod'
param apimApplicationInsightsName = 'appi-sfc--ia-eu-prod'
param apimApplicationInsightsDashboardName = 'dashboard-apim-sfc-dev-brs'
param foundryApplicationInsightsDashboardName = 'dashboard-foundry-sfc-dev-brs'
param keyVaultName = 'kv-sfc-ia-eu-prod'
param foundryName = 'aif-sfc-ia-eu-prod'

// ============================================================================
// MANAGED IDENTITY NAMES
// ============================================================================
param apimIdentityName = 'apim-sfc-ia-eu-prod'


// ============================================================================
// NETWORKING
// ============================================================================
// Deploy network-prerequisites.bicep before provisioning the hub.
param vnetName = 'vnet-sfc-ia-eu1'
param useExistingVnet = true
param existingVnetRG = 'rg-sfc-eu-ia-networking'
param manageExistingVnetSubnets = true
param vnetAddressPrefix = '10.189.0.0/16'

param apimSubnetName = 'snet-apim-sfc-dev-brs'
param apimSubnetPrefix = '10.223.2.0/26'
param privateEndpointSubnetName = 'snet-sfc-ia-iaas'
param privateEndpointSubnetPrefix = '10.189.0.0/26'

// Reserved for a later reporting phase; not provisioned while enableUsageReporting is false.
param functionAppSubnetName = 'snet-usage-sfc-dev-brs'
param functionAppSubnetPrefix = '10.223.2.128/26'

// Private DNS VNet links are managed separately from this deployment.
// An empty subscription ID uses the subscription selected in Azure CLI.
param dnsZoneRG = 'rg-bancoagrario-lab'
param dnsSubscriptionId = ''

param apimNetworkType = 'External'
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = true
param keyVaultExternalNetworkAccess = 'Disabled'
param foundryNetworkInjectionEnabled = false
param EventHubName = 'ehub-sfc-ia-eu-prod'
param CosmosDBName = 'cosmos-sfc-ia-eu-prod'

// ============================================================================
// FEATURES
// ============================================================================
param enableUsageReporting = false
param createAppInsightsDashboards = false
param enableAIModelInference = true
param enableDocumentIntelligence = false
param enableAzureAISearch = false
param enableAIGatewayPiiRedaction = true
param enableOpenAIRealtime = false
param entraAuth = false
param enableAPICenter = false
param enableManagedRedis = false
param enableUnifiedAiApi = true

// ============================================================================
// CAPACITY
// ============================================================================
param apimSku = 'StandardV2'
param apimSkuUnits = 1

// ============================================================================
// MICROSOFT FOUNDRY
// ============================================================================
param existingAiFoundry = {
  name: 'msassenus-1063-resource'
  resourceGroupName: 'rg-msassenus-1063'
}
param aiFoundryInstances = []
param aiFoundryModelsConfig = []
param primaryFoundryEmbeddingModelName = 'text-embedding-3-small'

// These deployments already exist in East US 2; only APIM registrations are created.
param existingLlmBackendConfig = [
  {
    backendId: 'sfc-existing-foundry'
    backendType: 'ai-foundry'
    endpoint: 'https://msassenus-1063-resource.cognitiveservices.azure.com/'
    authType: 'managed-identity'
    supportedModels: [
      {
        name: 'gpt-5.4-mini'
        modelFormat: 'OpenAI'
        modelVersion: '2026-03-17'
        sku: 'GlobalStandard'
        capacity: 500
        apiVersion: '2025-04-01-preview'
      }
      {
        name: 'text-embedding-3-small'
        modelFormat: 'OpenAI'
        modelVersion: '1'
        sku: 'Standard'
        capacity: 120
        apiVersion: '2024-10-21'
      }
    ]
    priority: 1
    weight: 100
  }
]
