@description('Region')
param location string

@description('DCR name')
param name string

@description('Log Analytics workspace resource id')
param workspaceId string

@description('Tags')
param tags object = {}

// DCR de syslog para hosts Linux Arc (via AMA).
//
// Nota: Change Tracking & Inventory se habilita por maquina via la extension
// ChangeTracking-Linux (que crea sus propias tablas/DCR la primera vez). Por
// eso este DCR se centra en syslog, que es util desde el minuto cero y no
// requiere tablas custom.
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'sysLogsDataSource'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'kern'
            'syslog'
            'user'
          ]
          logLevels: [
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'la-dest'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Syslog'
        ]
        destinations: [
          'la-dest'
        ]
      }
    ]
  }
}

output id string = dcr.id
output name string = dcr.name
