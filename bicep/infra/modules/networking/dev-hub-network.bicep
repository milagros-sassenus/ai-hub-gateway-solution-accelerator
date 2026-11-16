targetScope = 'resourceGroup'

param location string
param vnetName string
param vnetAddressPrefix string
param gatewayVnetId string
param gatewayVnetName string
param tags object = {}

// Subnets belong to the subsequent hub deployment; do not replace them on reruns.
resource vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource gatewayPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: vnet
  name: 'peer-to-${gatewayVnetName}'
  properties: {
    remoteVirtualNetwork: {
      id: gatewayVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output vnetId string = vnet.id
