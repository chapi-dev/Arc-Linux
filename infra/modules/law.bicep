@description('Region')
param location string

@description('Workspace name')
param name string

@description('Retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Daily ingestion cap GB (-1 = sin limite)')
param dailyQuotaGb int = -1

@description('Tags')
param tags object = {}

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output id string = law.id
output customerId string = law.properties.customerId
output name string = law.name
