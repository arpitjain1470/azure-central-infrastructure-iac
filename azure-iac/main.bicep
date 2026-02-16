targetScope = 'subscription'

param deployRG bool = true
param deployNSG bool = true
param deployUDR bool = true
param deployVNet bool = true
param deploylb bool = true
param deploypeering bool = true
param tags object = {}

param rgName string
param location string

param vnets array = []
param nsgs array = []
param udrs array = []
param peerings array = []

param additionalResourceGroups array = []

module rg './modules/resourcegroup/rg.bicep' = if (deployRG) {
  name: 'rg-${rgName}'
  scope: subscription()
  params: { rgName: rgName, location: location }
}

module addRgs './modules/resourcegroup/rg.bicep' = [for ar in additionalResourceGroups: {
  name: 'rg-${ar.name}'
  scope: subscription()
  params: {
    rgName: ar.name
    location: empty(ar.location) ? location : ar.location
    tags: empty(ar.tags) ? {} : ar.tags
  }
}]



module nsg './modules/network/nsg.bicep' = [
  for n in nsgs: if (deployNSG) {
    name: 'nsg-${n.name}'
    scope: resourceGroup(rgName)
    params: {
      nsgName: n.name
      location: location
      securityRules: n.rules
      tags: tags
    }
    dependsOn: [ rg ]
  }
]

module udr './modules/network/udr.bicep' = [
  for u in udrs: if (deployUDR) {
    name: 'udr-${u.name}'
    scope: resourceGroup(rgName)
    params: {
      routeTableName: u.name
      location: location
      routes: u.routes
      tags: tags
    }
    dependsOn: [ rg ]
  }
]

module vnet './modules/network/vnet.bicep' = [
  for v in vnets: if (deployVNet) {
    name: 'vnet-${v.vnetName}'
    scope: resourceGroup(rgName)
    params: {
      vnetName: v.vnetName
      location: location
      tags: tags
      addressSpace: v.addressSpace
      subnets: [
        for s in v.subnets: {
          name: s.name
          prefix: s.prefix
          nsgId: empty(s.?nsgName) ? null : resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', s.nsgName)
          udrId: empty(s.?udrName) ? null : resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/routeTables', s.udrName)
        }
      ]
      dnsServers: contains(v, 'dnsServers') ? v.dnsServers : []
    }
    dependsOn: [ rg, nsg, udr ]
  }
]

param lbs array = []

resource lbRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = [
  for l in lbs: if (deploylb && !empty(l.?resourceGroupName)) {
    name: l.resourceGroupName
  }
]

module lb_additional './modules/network/lb.bicep' = [
  for (l, i) in lbs: if (deploylb && !empty(l.?resourceGroupName)) {
    name: 'lb-${l.lbName}'
    scope: resourceGroup(subscription().subscriptionId, l.resourceGroupName)
    params: {
      lbName: l.lbName
      location: lbRg[i].location     // ← auto-uses the target RG’s location
      tags: tags
      sku: empty(l.sku) ? { name: 'Standard', tier: 'Regional' } : l.sku
      frontendConfigs: l.?frontendConfigs ?? []
      backendPoolName: l.?backendPoolName ?? ''
      probes: l.?probes ?? []
      rules: l.?rules ?? []
    }
    dependsOn: [
      addRgs
      nsg
      udr
      vnet
    ]
  }
]

module peering './modules/network/peering.bicep' = [
  for p in peerings: if (deploypeering) {
    name: 'peering-${p.peeringName}'
    scope: resourceGroup(rgName)
    params: {
      sourceVnetName: p.sourceVnetName
      remoteVnetId: p.remoteVnetId
      peeringName: p.peeringName
      allowForwardedTraffic: p.allowForwardedTraffic
      allowGatewayTransit: p.allowGatewayTransit
      useRemoteGateways: p.useRemoteGateways
    }
    dependsOn: [ vnet ]
  }
]