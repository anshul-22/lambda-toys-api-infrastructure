param location string
param prefix string
param vnetId string
param containerRegistryName string
param containerRegistryUsername string
@secure()
param containerRegistryPassword string
param containerVersion string

// param cosmosDbName string 
// param cosmosContainerName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: '${prefix}-la-wokspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${prefix}-container-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: '${vnetId}/subnets/acaControlPlaneSubnet'
    }
  }
}

resource apiApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${prefix}-api-container'
  location: location
  kind: 'containerapp'
  properties: {
    environmentId: env.id
    configuration: {
      secrets: [
        {
          name: 'container-registry-password'
          value: containerRegistryPassword
        }
      ]
      registries: [
        {
          server: '${containerRegistryName}.azurecr.io'
          username: containerRegistryUsername
          passwordSecretRef: 'container-registry-password'
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
      }
    }
    template: {
      containers: [
        {
          image: '${containerRegistryName}.azurecr.io/hello-k8s-node:${containerVersion}'
          name: 'lambdaapi'
          resources: {
            cpu: '0.5'
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
      }
    }
  }
}

output apiUrl string = apiApp.properties.configuration.ingress.fqdn
