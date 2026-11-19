targetScope = 'resourceGroup'

param vnetName string
param location string
param apimSku string
param apimSubnetName string
param apimSubnetPrefix string
param apimNsgName string
param privateEndpointSubnetName string
param privateEndpointSubnetPrefix string
param functionAppSubnetName string
param functionAppSubnetPrefix string
param tags object = {}
param enableFunctionAppSubnet bool = true
param managePrivateEndpointSubnet bool = true
param reservedSubnets { name: string, addressPrefix: string, networkSecurityGroupId: string? }[] = []
param apimFirewallIp string = ''
param apimRouteTableName string = 'rt-${apimSubnetName}'

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: apimNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

var apimDelegation = apimSku == 'PremiumV2' ? 'Microsoft.ApiManagement/service' : 'Microsoft.Web/serverFarms'

resource apimRouteTable 'Microsoft.Network/routeTables@2023-11-01' = if (!empty(apimFirewallIp)) {
  name: apimRouteTableName
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: apimFirewallIp
        }
      }
      {
        name: 'apim-management'
        properties: {
          addressPrefix: 'ApiManagement'
          nextHopType: 'Internet'
        }
      }
    ]
  }
}

module apimSubnet './subnet.bicep' = {
  name: 'apim-subnet'
  params: {
    name: apimSubnetName
    vnetName: vnetName
    vnetRG: resourceGroup().name
    properties: union({
      addressPrefix: apimSubnetPrefix
      networkSecurityGroup: {
        id: apimNsg.id
      }
      delegations: contains(['StandardV2', 'PremiumV2'], apimSku) ? [
        {
          name: apimDelegation
          properties: {
            serviceName: apimDelegation
          }
        }
      ] : []
    }, !empty(apimFirewallIp) ? {
      routeTable: {
        id: apimRouteTable!.id
      }
    } : {})
  }
}

module privateEndpointSubnet './subnet.bicep' = if (managePrivateEndpointSubnet) {
  name: 'private-endpoint-subnet'
  params: {
    name: privateEndpointSubnetName
    vnetName: vnetName
    vnetRG: resourceGroup().name
    properties: {
      addressPrefix: privateEndpointSubnetPrefix
      privateEndpointNetworkPolicies: 'Disabled'
    }
  }
  dependsOn: [
    apimSubnet
  ]
}

module functionAppSubnet './subnet.bicep' = if (enableFunctionAppSubnet) {
  name: 'logic-app-subnet'
  params: {
    name: functionAppSubnetName
    vnetName: vnetName
    vnetRG: resourceGroup().name
    properties: {
      addressPrefix: functionAppSubnetPrefix
      delegations: [
        {
          name: 'Microsoft.Web/serverFarms'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ]
    }

  }
  dependsOn: [
    apimSubnet
    privateEndpointSubnet
  ]
}

@batchSize(1)
module reservations './subnet.bicep' = [for (subnet, index) in reservedSubnets: {
  name: 'reserved-subnet-${index}'
  params: {
    name: subnet.name
    vnetName: vnetName
    vnetRG: resourceGroup().name
    properties: union({
      addressPrefix: subnet.addressPrefix
    }, !empty(subnet.?networkSecurityGroupId ?? '') ? {
      networkSecurityGroup: {
        id: subnet.networkSecurityGroupId!
      }
    } : {})
  }
  dependsOn: [
    functionAppSubnet
    privateEndpointSubnet
    apimSubnet
  ]
}]
