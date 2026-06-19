// =============================================================================
// main.bicep – Arc-Linux lab infra (RG scope)
// Despliega:
//   - Log Analytics Workspace (LAW)
//   - Data Collection Rule para Change Tracking & Inventory (Linux)
//   - 3 Maintenance Configurations (anillos R0 Tue, R1 Thu, R2 Sat biweekly)
//
// Las dynamic scopes (filtros por tag) y los policy assignments se crean
// desde scripts/deploy/deploy.ps1 ya que estan mejor soportados via CLI.
// =============================================================================
targetScope = 'resourceGroup'

@description('Region donde desplegar (recursos staticos)')
param location string = resourceGroup().location

@description('Tags comunes')
param tags object = {
  purpose: 'arc-linux'
  managedBy: 'arc-linux-repo'
  env: 'lab'
}

@description('Nombre base; se usa para componer LAW, DCR, MCs')
param namePrefix string = 'arc-linux-lab'

@description('Fecha-hora de arranque inicial de las MCs (yyyy-MM-dd HH:mm). Debe ser futuro.')
param baseStart string = '2026-07-07 22:00'

@description('Time zone para las MCs')
param timeZone string = 'Romance Standard Time'

// -----------------------------------------------------------------------------
// LAW
// -----------------------------------------------------------------------------
module law 'modules/law.bicep' = {
  name: 'lawDeployment'
  params: {
    name: 'law-${namePrefix}'
    location: location
    retentionInDays: 30
    dailyQuotaGb: 5
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// DCR para CT&I + syslog
// -----------------------------------------------------------------------------
module dcr 'modules/dcr.bicep' = {
  name: 'dcrDeployment'
  params: {
    name: 'dcr-${namePrefix}-syslog'
    location: location
    workspaceId: law.outputs.id
    tags: tags
  }
}

// -----------------------------------------------------------------------------
// Maintenance Configurations (anillos)
// -----------------------------------------------------------------------------
module mcR0 'modules/maintenance.bicep' = {
  name: 'mcR0'
  params: {
    name: 'mc-${namePrefix}-r0-weekly'
    location: location
    startDateTime: baseStart
    timeZone: timeZone
    recurEvery: '1Week Tuesday'
    duration: '03:30'
    rebootSetting: 'IfRequired'
    classificationsToInclude: [ 'Critical', 'Security' ]
    packageNameMasksToExclude: [ 'kernel*', 'grub*' ]
    tags: union(tags, { ring: 'R0' })
  }
}

module mcR1 'modules/maintenance.bicep' = {
  name: 'mcR1'
  params: {
    name: 'mc-${namePrefix}-r1-weekly'
    location: location
    startDateTime: baseStart
    timeZone: timeZone
    recurEvery: '1Week Thursday'
    duration: '03:30'
    rebootSetting: 'IfRequired'
    classificationsToInclude: [ 'Critical', 'Security' ]
    packageNameMasksToExclude: []
    tags: union(tags, { ring: 'R1' })
  }
}

module mcR2 'modules/maintenance.bicep' = {
  name: 'mcR2'
  params: {
    name: 'mc-${namePrefix}-r2-biweekly'
    location: location
    startDateTime: baseStart
    timeZone: timeZone
    recurEvery: '2Week Saturday'
    duration: '03:30'
    rebootSetting: 'IfRequired'
    classificationsToInclude: [ 'Critical', 'Security', 'Other' ]
    packageNameMasksToExclude: []
    tags: union(tags, { ring: 'R2' })
  }
}

// -----------------------------------------------------------------------------
// Outputs (consumidos por deploy.ps1)
// -----------------------------------------------------------------------------
output lawId string = law.outputs.id
output lawName string = law.outputs.name
output dcrId string = dcr.outputs.id
output dcrName string = dcr.outputs.name
output mcR0Id string = mcR0.outputs.id
output mcR1Id string = mcR1.outputs.id
output mcR2Id string = mcR2.outputs.id
output mcR0Name string = mcR0.outputs.name
output mcR1Name string = mcR1.outputs.name
output mcR2Name string = mcR2.outputs.name
