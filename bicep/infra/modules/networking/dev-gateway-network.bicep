targetScope = 'resourceGroup'

param gatewayVnetName string
param hubVnetName string
param hubVnetId string
param internalDnsZoneName string
param tags object = {}

resource gatewayVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: gatewayVnetName
}

resource hubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: gatewayVnet
  name: 'peer-to-${hubVnetName}'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource apimDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azure-api.net'
  location: 'global'
  tags: tags
}

resource apimDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for network in [
  {
    name: hubVnetName
    id: hubVnetId
  }
  {
    name: gatewayVnetName
    id: gatewayVnet.id
  }
]: {
  parent: apimDnsZone
  name: 'link-${network.name}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: network.id
    }
  }
}]

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
}

resource keyVaultHubDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: 'link-${hubVnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnetId
    }
  }
}

resource internalDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: internalDnsZoneName
}

resource internalHubDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: internalDnsZone
  name: 'link-${hubVnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnetId
    }
  }
}
