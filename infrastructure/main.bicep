param location string
param prefix string
param vnetSettings object = {
  addressPrefixes: [
    '10.0.0.0/20'
  ]
  subnets: [
    {
      name: 'subnet1'
      addressPrefix: '10.0.0.0/22'
    }
    {
      name: 'acaAppSubnet'
      addressPrefix: '10.0.4.0/22'
    }
    {
      name: 'acaControlPlaneSubnet'
      addressPrefix: '10.0.8.0/22'
    }
  ]
}
param containerVersion string

module core 'core.bicep' = {
  name: 'core'
  params: {
    location: location
    prefix: prefix
    vnetSettings: vnetSettings
  }
}

resource secretKeyVault 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
 name:core.outputs.secretKeyVaultName
}


module aca 'aca.bicep' = {
  name: 'aca'
  dependsOn:[
    core
  ]
  params: {
    location: location
    containerRegistryName: core.outputs.containerRegistryName
    containerRegistryPassword: secretKeyVault.getSecret(core.outputs.containerRegistrySecret)
    containerRegistryUsername: core.outputs.containerRegistryUsername
    containerVersion: containerVersion
    prefix: prefix
    vnetId: core.outputs.vnetId
  }
}
