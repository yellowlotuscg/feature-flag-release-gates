targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location
@description('Globally unique Container App name, using a placeholder in examples.')
param appName string = 'pricing-api-example'
@description('Container Apps environment name.')
param environmentName string = 'pricing-env-example'
@description('Globally unique App Configuration store name.')
param appConfigName string = 'pricing-config-example'
@description('Log Analytics workspace name.')
param logAnalyticsName string = 'pricing-logs-example'
@description('Image reference published by the deployment workflow.')
param containerImage string = 'ghcr.io/ORG/REPO/pricing-api:latest'
@description('GitHub organization or user for OIDC subject construction.')
param githubOrg string = 'YOUR_GITHUB_ORG'
@description('GitHub repository name for OIDC subject construction.')
param githubRepo string = 'feature-flag-release-gates'
@description('GitHub environment used by the deployment workflow.')
param githubEnvironment string = 'production'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: appConfigName
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource githubIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${appName}-github'
  location: location
}

resource githubFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'github-${githubEnvironment}'
  parent: githubIdentity
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOrg}/${githubRepo}:environment:${githubEnvironment}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${githubIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
      }
    }
    template: {
      containers: [
        {
          name: 'pricing-api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              name: 'AzureAppConfigurationEndpoint'
              value: appConfig.properties.endpoint
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource appConfigDataReader 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '516239f1-63e1-4d78-a4de-a74fb236a071'
}

resource appConfigRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfig.id, containerApp.id, appConfigDataReader.id)
  scope: appConfig
  properties: {
    roleDefinitionId: appConfigDataReader.id
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output appConfigEndpoint string = appConfig.properties.endpoint
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output githubFederatedClientId string = githubIdentity.properties.clientId
output githubIdentityPrincipalId string = githubIdentity.properties.principalId
