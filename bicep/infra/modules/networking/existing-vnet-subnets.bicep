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

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: apimNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

var apimDelegation = apimSku == 'PremiumV2' ? 'Microsoft.ApiManagement/service' : 'Microsoft.Web/serverFarms'

module apimSubnet './subnet.bicep' = {
  name: 'apim-subnet'
  params: {
    name: apimSubnetName
    vnetName: vnetName
    vnetRG: resourceGroup().name
    properties: {
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
    }
  }
}

module privateEndpointSubnet './subnet.bicep' = {
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
    privateEndpointSubnet
  ]
}
