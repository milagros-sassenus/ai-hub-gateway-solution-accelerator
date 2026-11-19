using '../main.bicep'

// Initial subscription-scoped deployment, not an APIM gateway upgrade.
// Subscription selection comes from Azure CLI; no subscription ID is pinned here.

// ============================================================================
// BASIC PARAMETERS
// ============================================================================
param environmentName = 'sfc-aihub-prod'
param location = 'eastus'
param apicLocation = 'eastus'
param resourceGroupName = 'rg-sfc-ia-eu-prod'
param tags = {
  Environment: 'Production'
  Workload: 'AI Hub'
  SecurityControl: 'Ignore'
}

// ============================================================================
// RESOURCE NAMES
// ============================================================================
param apimServiceName = 'apim-sfc-ia-eu-prod'
param logAnalyticsName = 'law-sfc-ia-eu-prod'
param apimApplicationInsightsName = 'appi-sfc-ia-eu-prod'
param apimApplicationInsightsDashboardName = 'dsh-appi-sfc-ai-eu-prod'
param funcApplicationInsightsDashboardName = 'dsh-func-sfc-ai-eu-prod'
param foundryApplicationInsightsDashboardName = 'dsh-foundry-sfc-ai-eu-prod'
param keyVaultName = 'kv-sfc-ia-eu-prod'
param aiFoundryResourceName = 'aif-sfc-ia-eu-prod'
param usageProcessingLogicAppName = 'logic-sfc-ia-eu-prod'
// Original customer label: db-storage-sfc-ia-eu-prod (not a valid Azure Storage account name).
param storageAccountName = 'stsfciaeuprod'

// ============================================================================
// MANAGED IDENTITY NAMES
// ============================================================================
param apimIdentityName = 'id-sfc-ia-eu-apim-prod'
param cosmosIdentityName = 'id-sfc-ia-eu-cosmos-prod'
param usageLogicAppIdentityName = 'id-sfc-ia-eu-logic-prod'


// ============================================================================
// NETWORKING
// ============================================================================
// The VNet must already exist. See README.md for customer/lab prerequisites.
param vnetName = 'vnet-sfc-ia-eu1'
param useExistingVnet = true
param existingVnetRG = 'rg-sfc-eu-ia-networking'
param manageExistingVnetSubnets = true
// Customer: shared subnet already exists. Lab: set true to create it.
param managePrivateEndpointSubnet = false
param vnetAddressPrefix = '10.189.0.0/16'

param apimSubnetName = 'snet-sfc-ia-eu-prod-apim'
param apimSubnetPrefix = '10.189.2.0/26'
param privateEndpointSubnetName = 'snet-sfc-ia-iaas'
param privateEndpointSubnetPrefix = '10.189.0.0/26'

var agwSubnetName = 'snet-sfc-ia-eu-prod-agw'
var agwSubnetPrefix = '10.189.2.64/26'

var foundrySubnetName = 'snet-sfc-ia-eu-prod-aif'
var foundrySubnetPrefix = '10.189.3.0/24'

var logicSubnetName = 'snet-sfc-ia-eu-prod-logic'
var logicSubnetPrefix = '10.189.2.128/27'

// Existing template names functionAppSubnet* represent the active Logic App subnet.
var reservedFunctionAppSubnetName = 'snet-sfc-ia-eu-prod-func'
var reservedFunctionAppSubnetPrefix = '10.189.4.0/24'
param functionAppSubnetName = logicSubnetName
param functionAppSubnetPrefix = logicSubnetPrefix
param reservedSubnets = [
  { name: agwSubnetName, addressPrefix: agwSubnetPrefix }
  { name: foundrySubnetName, addressPrefix: foundrySubnetPrefix }
  { name: reservedFunctionAppSubnetName, addressPrefix: reservedFunctionAppSubnetPrefix }
]

param storageBlobPrivateEndpointName = 'pe-st-blob-sfc-ia-eu-prod'
param storageFilePrivateEndpointName = 'pe-st-file-sfc-ia-eu-prod'
param storageTablePrivateEndpointName = 'pe-st-table-sfc-ia-eu-prod'
param storageQueuePrivateEndpointName = 'pe-st-queue-sfc-ia-eu-prod'
param cosmosDbPrivateEndpointName = 'pe-cosmos-sfc-ia-eu-prod'
param eventHubPrivateEndpointName = 'pe-ehub-sfc-ia-eu-prod'
param apimV2PrivateEndpointName = 'pe-apim-sfc-ia-eu-prod'
param keyVaultPrivateEndpointName = 'pe-kv-sfc-ia-eu-prod'
// Retained for when logicAppUsePrivateEndpoint is enabled.
param logicAppPrivateEndpointName = 'pe-logic-sfc-ia-eu-prod'

// Private DNS VNet links are managed separately from this deployment.
// An empty subscription ID uses the subscription selected in Azure CLI.
param dnsZoneRG = 'rg-bancoagrario-lab'
param dnsSubscriptionId = ''
var dnsOpenAiId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
var dnscognitiveServicesId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
var dnsiaServicesId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
var dnskeyVaultId = '/subscriptions/b1f1766a-87af-4e43-a661-b180027e7361/resourceGroups/rg-sfc-eu-ia-networking/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
var dnsmonitorId = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-eu-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.monitor.azure.com'
var dnsserviceBusId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net'
var dnscosmosDbId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
var dnsStorageAccount = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-eu-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
var dnsStorageFileId = '/subscriptions/0969cbf2-bc92-4049-9912-768db3a13b00/resourceGroups/rg-sfc-eu-hub-networking/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
var dnsAzureAPI = '/subscriptions/05a0e57b-2fd4-4141-bbac-b2192658c148/resourceGroups/rg-hub-dns-centralus/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net'
var dnsTableId = '/subscriptions/b1f1766a-87af-4e43-a661-b180027e7361/resourceGroups/rg-sfc-eu-ia-networking/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net'
var dnsqueueID = '/subscriptions/ec7e00be-f46d-43ad-98fe-9d7a70b1ba1c/resourceGroups/rg-sfc-prod-networking/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net'
param existingPrivateDnsZones = {
  openai: dnsOpenAiId
  cognitiveServices: dnscognitiveServicesId
  aiServices: dnsiaServicesId
  keyVault: dnskeyVaultId
  monitor: dnsmonitorId
  eventHub: dnsserviceBusId
  cosmosDb: dnscosmosDbId
  storageBlob: dnsStorageAccount
  storageFile: dnsStorageFileId
  apimGateway: dnsAzureAPI
  storageTable: dnsTableId
  storageQueue: dnsqueueID
}

param apimNetworkType = 'External'
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = true
param logicAppUsePrivateEndpoint = false
param logicAppPublicNetworkAccess = true
param aiFoundryExternalNetworkAccess = 'Disabled'
param keyVaultExternalNetworkAccess = 'Disabled'
param foundryNetworkInjectionEnabled = false
param eventHubNamespaceName = 'ehub-sfc-ia-eu-prod'
param cosmosDbAccountName = 'cosmos-sfc-ia-eu-prod'

// ============================================================================
// FEATURES
// ============================================================================
param enableUsageReporting = true
param createAppInsightsDashboards = true
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
param eventHubCapacityUnits = 1
param cosmosDbRUs = 400
param logicAppsSkuCapacityUnits = 1

// ============================================================================
// MICROSOFT FOUNDRY
// ============================================================================
// This selects only the Foundry alternative, not a complete lab network profile.
var useExistingLabFoundry = false
var existingLabFoundry = {
  name: 'proj-clasificaciondemandas-prod'
  resourceGroupName: 'rg-msassenus-1063'
}
param existingAiFoundry = useExistingLabFoundry ? existingLabFoundry : null
param aiFoundryInstances = useExistingLabFoundry ? [] : [
  {
    name: 'aif-sfc-ia-eu-prod'
    location: 'eastus'
    customSubDomainName: 'aif-sfc-ia-eu-prod'
    defaultProjectName: 'proj-clasificaciondemandas-prod'
  }
]
// Catalog model names also become deployment names; distinct aliases are not configured here.
param aiFoundryModelsConfig = useExistingLabFoundry ? [] : [
  {
    name: 'gpt-6-luna'
    publisher: 'OpenAI'
    version: '2026-09-22'
    sku: 'GlobalStandard'
    capacity: 120
    retirementDate: '2028-03-10'
    aiserviceIndex: 0
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 150
    retirementDate: '2028-02-08'
    aiserviceIndex: 0
  }
]
param primaryFoundryEmbeddingModelName = useExistingLabFoundry ? 'text-embedding-3-small' : 'text-embedding-3-large'

// Preserved lab alternative: existing East US 2 deployments, registered in APIM only.
param existingLlmBackendConfig = useExistingLabFoundry ? [
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
] : []

// ============================================================================
// FIREWALL
// ============================================================================
// dentro de la misma vnet no pasa x el firewall!
param apimFirewallIp = '10.182.0.6'