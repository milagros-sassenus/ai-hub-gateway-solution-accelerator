targetScope = 'subscription'

param resourceGroupName string
param location string
param vnetName string
param vnetAddressPrefix string
param gatewayResourceGroupName string
param gatewayVnetName string
param internalDnsZoneName string
param tags object = {}

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module hubNetwork '../modules/networking/dev-hub-network.bicep' = {
  name: 'dev-hub-network'
  scope: hubResourceGroup
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    gatewayVnetId: resourceId(subscription().subscriptionId, gatewayResourceGroupName, 'Microsoft.Network/virtualNetworks', gatewayVnetName)
    gatewayVnetName: gatewayVnetName
    tags: tags
  }
}

module gatewayNetwork '../modules/networking/dev-gateway-network.bicep' = {
  name: 'dev-gateway-network'
  scope: resourceGroup(gatewayResourceGroupName)
  params: {
    gatewayVnetName: gatewayVnetName
    hubVnetName: vnetName
    hubVnetId: hubNetwork.outputs.vnetId
    internalDnsZoneName: internalDnsZoneName
    tags: tags
  }
}

output vnetId string = hubNetwork.outputs.vnetId
output dnsZoneResourceGroupName string = gatewayResourceGroupName
