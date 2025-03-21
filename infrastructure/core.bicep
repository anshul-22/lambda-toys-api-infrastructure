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

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: '${prefix}-default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allowhttpsinbound'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          description: 'Allow https traffic into API'
          sourceAddressPrefix: '81.80.72.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          priority: 200
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetSettings.addressPrefixes
    }
    subnets: [
      for subnet in vnetSettings.subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'disabled'
        }
      }
    ]
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-03-15' = {
  name: '${prefix}-cosmos-account-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
      maxStalenessPrefix: 1
      maxIntervalInSeconds: 5
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-06-15' = {
  name: '${prefix}-sqldb'
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: '${prefix}-sqldb'
    }
    options: {}
  }
}

resource sqlContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-06-15' = {
  parent: sqlDb
  name: '${prefix}-orders'
  properties: {
    resource: {
      id: '${prefix}-orders'
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
    }
    options: {}
  }
}

resource stateContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: sqlDb
  name: '${prefix}-state'
  properties: {
    resource: {
      id: '${prefix}-state'
      partitionKey: {
        paths: [
          '/partitionKey'
        ]
      }
    }
    options: {}
  }
}

resource cosmosPrivateDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}

resource cosmosPrivateDnsNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${prefix}-cosmos-dns-link'
  location: 'global'
  parent: cosmosPrivateDns
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: '${prefix}-cosmos-pe'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${prefix}-cosmos-pe'
        properties: {
          privateLinkServiceId: cosmosDbAccount.id
          groupIds: [
            'SQL'
          ]
        }
      }
    ]
    subnet: {
      id: virtualNetwork.properties.subnets[0].id
    }
  }
}

resource privateEndpoitntDnsLink 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: '${prefix}-cosmos-pe-dns'
  parent: cosmosPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink.documents.azure.com'
        properties: {
          privateDnsZoneId: cosmosPrivateDns.id
        }
      }
    ]
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: '${replace(prefix,'-','')}acranshul'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${prefix}-kv-poc'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
  }
}

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${keyVault.name}/acrAdminPassword'
  properties: {
    value: containerRegistry.listCredentials().passwords[0].value
  }
}

output vnetId string = virtualNetwork.id
output containerRegistryName string = containerRegistry.name
output containerRegistryUsername string = containerRegistry.name
output secretKeyVaultName string = keyVault.name
output containerRegistrySecret string = split(keyVaultSecret.name, '/')[1]
output cosmosAccountName string = cosmosDbAccount.name
output cosmosDbName string = sqlDb.name
output cosmosStateContainerName string = stateContainer.name
output cosmosSqlContainerName string = sqlContainer.name
