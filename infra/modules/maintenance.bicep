@description('Region')
param location string

@description('Maintenance Configuration name')
param name string

@description('Tags')
param tags object = {}

@description('Start date-time (yyyy-MM-dd HH:mm)')
param startDateTime string

@description('TZ database name (ej. Romance Standard Time, UTC, W. Europe Standard Time)')
param timeZone string = 'Romance Standard Time'

@description('Duration HH:mm (min 01:30, max 03:55)')
param duration string = '03:30'

@description('RRULE recurrence (ej. Week Tuesday, Week Thursday, 2Week Saturday)')
param recurEvery string = '1Week Tuesday'

@description('Reboot setting')
@allowed([ 'IfRequired', 'Never', 'Always' ])
param rebootSetting string = 'IfRequired'

@description('Linux package name masks to exclude')
param packageNameMasksToExclude array = []

@description('Linux classifications to include')
param classificationsToInclude array = [ 'Critical', 'Security' ]

resource mc 'Microsoft.Maintenance/maintenanceConfigurations@2023-04-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    maintenanceScope: 'InGuestPatch'
    extensionProperties: {
      InGuestPatchMode: 'User'
    }
    maintenanceWindow: {
      startDateTime: startDateTime
      duration: duration
      timeZone: timeZone
      recurEvery: recurEvery
    }
    installPatches: {
      rebootSetting: rebootSetting
      linuxParameters: {
        classificationsToInclude: classificationsToInclude
        packageNameMasksToExclude: packageNameMasksToExclude
      }
      windowsParameters: {}
    }
  }
}

output id string = mc.id
output name string = mc.name
