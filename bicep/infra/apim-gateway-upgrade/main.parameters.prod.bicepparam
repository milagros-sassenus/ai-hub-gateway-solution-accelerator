using '../main.bicep'

// Initial subscription-scoped deployment, not an APIM gateway upgrade.
// Subscription selection comes from Azure CLI; no subscription ID is pinned here.

// ============================================================================
// BASIC PARAMETERS
// ============================================================================
param environmentName = 'rg-sfc-ia-eu-prod'
param location = 'eastus'
param apicLocation = 'eastus'
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
param logicAppName = 'logic-sfc-ia-eu-prod' 
param storageAccount = 'db-storage-sfc-ia-eu-prod'

// ============================================================================
// MANAGED IDENTITY NAMES
// ============================================================================
param apimIdentityName = 'id-sfc-ia-eu-apim-prod'
param cosmosIdentityName = 'id-sfc-ia-eu-cosmos-prod'
param logicAppIdentityName = 'id-sfc-ia-eu-logic-prod'


// ============================================================================
// NETWORKING
// ============================================================================
// Deploy network-prerequisites.bicep before provisioning the hub.
param vnetName = 'vnet-sfc-ia-eu1'
param useExistingVnet = true
param existingVnetRG = 'rg-sfc-eu-ia-networking'
param manageExistingVnetSubnets = true
param vnetAddressPrefix = '10.189.0.0/16'

param apimSubnetName = 'snet-sfc-ia-eu-prod-apim'
param apimSubnetPrefix = '10.189.2.0/26'
param privateEndpointSubnetName = 'snet-sfc-ia-iaas'
param privateEndpointSubnetPrefix = '10.189.0.0/26'

param agwSubnetName = 'snet-sfc-ia-eu-prod-agw'
param agwSubnetPrefix = '10.189.2.64/26'

param foundrySubnetName = 'snet-sfc-ia-eu-prod-aif'
param foundrySubnetPrefix = '10.189.3.0/24'

param logicSubnetName = 'snet-sfc-ia-eu-prod-logic'
param logicSubnetPrefix = '10.189.2.128/27'

// Reserved for a later reporting phase; not provisioned while enableUsageReporting is false.
param functionAppSubnetName = 'snet-sfc-ia-eu-prod-func'
param functionAppSubnetPrefix = '10.189.4.0/24'

// Private DNS VNet links are managed separately from this deployment.
// An empty subscription ID uses the subscription selected in Azure CLI.
param dnsZoneRG = 'rg-bancoagrario-lab'
param dnsSubscriptionId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
param dnscognitiveServicesId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
param dnsiaServicesId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
param dnskeyVaultId = '/subscriptions/b1f1766a-87af-4e43-a661-b180027e7361/resourceGroups/rg-sfc-eu-ia-networking/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
param dnsmonitorId = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-eu-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.monitor.azure.com'
param dnsserviceBusId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net'
param dnscosmosDbId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
param dnsStorageAccount = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-eu-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net' 
param dnsAzureAPI = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net'
param dnsTableId = '/subscriptions/b1f1766a-87af-4e43-a661-b180027e7361/resourceGroups/rg-sfc-eu-ia-networking/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net'
param dnsqueueID = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net'

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
  name: 'proj-clasificaciondemandas-prod'
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
        name: 'gpt-6-luna'
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

// ============================================================================
// MICROSOFT FOUNDRY
// ============================================================================
// dentro de la misma vnet no pasa x el firewall!
paramIpFirewall= '10.182.0.6'