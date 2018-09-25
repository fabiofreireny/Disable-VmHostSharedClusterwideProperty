<#
    .SYNOPSIS
    In ESX, changes "shared-clusterwide" property of LUNS of a specific size

    .DESCRIPTION
    When an ESX has its boot volume on shared storage, VMware assumes it's supposed to be shared and flags it as such.
    When using Host Profiles this creates a compliance failure as the boot volume is never shared.
    The resolution is to flag each boot volume (in each host) as non-shared.

    NOTE: The script assumes you're already connected to your vSphere

    .EXAMPLE
     Disable-VmHostSharedClusterwideProperty.ps1 -VmHost esxhost.domain.local -esxCredential (get-credential)
     Prompts for ESX credentials (SSH, usually root) and changes property

     .EXAMPLE
     $cred = get-credential; (1,5,7) | Disable-VmHostSharedClusterwideProperty.ps1 -VmHost esx0$($_).domain.local -esxCredential $cred

     Iterates through three ESX hosts (esx01, esx05 and esx07), changing property

     .LINK
    https://github.com/fabiofreireny/Disable-VmHostSharedClusterwideProperty
    https://www.powershellgallery.com/packages/Posh-SSH
    http://www.yellow-bricks.com/2015/03/19/host-profile-noncompliant-when-using-local-sas-drives-with-vsphere-6/

    .NOTES
    Author: Fabio Freire (@fabiofreireny)

    Requires Posh-SSH module
    Requires VMware PowerCLI
#>

#requires -module Posh-SSH
#requires -module VMware.VimAutomation.Core

[CmdletBinding(SupportsShouldProcess,ConfirmImpact="Low")]
param(
    #ESX Host Name
    [Parameter(Mandatory=$True)]
    [string]$VmHost,
    #SSH Credential
    [Parameter(Mandatory=$True)]
    [pscredential]$esxCredential,
    #LUN Size (in MB) whose property should be changed (default = 10GB)
    [decimal]$LunSize = 10240
)

#region Initialize
# Ensure you're connected to vSphere
if (-not $global:DefaultVIServers) {
    Write-Output "You're not connected to any vSphere servers"
    Write-Output "Connect to vSphere then re-run this command"
    Break
}

# Enable SSH
$vmHostService = Get-VMHost $vmHost | Get-VMHostService | ? Label -eq SSH
$vmHostService | Start-VMHostService -WhatIf:$false | Out-Null

# Connect to host
$session = New-SSHSession -ComputerName $vmHost -Credential $esxCredential -AcceptKey
#endregion

# Get all Device IDs
$deviceIDs = @()
$dump = (Invoke-SSHCommand -SSHSession $session -Command "esxcli storage core device list | grep 'Devfs Path'").output.split("/")
# Evey 5th line contains the WWID
for ($i=4;$i -le $dump.count;$i=$i+5) { $deviceIDs += $dump[$i] }

$matchedLUNs = @()
# Find the deviceID that is exactly 10GB, since this is how big the boot volume is
$deviceIDs | % {
    $deviceID = $_
    $size = (Invoke-SSHCommand -SSHSession $session -Command "esxcli storage core device list --device $deviceID | grep '  Size'").output.split(" ")[4]
    #Write-Output "$deviceID, $size"
    if ($size -eq $LunSize) {
        $matchedLUNs += $deviceID
    }
}

# This performs the actual change. Supports -WhatIf
function configureLUN {
    param (
        [string]$LUN
    )
    if ($PSCmdlet.ShouldProcess("$LUN","Disable [Shared ClusterWide] setting")) {
        Invoke-SSHCommand -SSHSession $session -Command "esxcli storage core device setconfig --device $LUN --shared-clusterwide=false"
    }
}

# Figure out what to do
switch ($matchedLUNs.count) {
    0 { Write-Output "Found no LUNs that are exactly 10GB in size. Skipping." }
    1 { Write-Output "Found one LUN $matchedLUNs that is 10GB in size. Will configure that."
        configureLUN -LUN $matchedLUNs
    }
    2 { Write-Output "Found multiple LUNs that are 10GB in size. I don't know which one to configure."
        $matchedLUNs | % {
            if ((read-host "Configure $_ (y/n) ?").toUpper() -eq "Y") {
                configureLUN -LUN $_
            }
        }
    }
}

#region CleanUp
# Terminate SSH session and disable SSH service on host
Remove-SSHSession -SSHSession $session | Out-Null
$vmHostService | Stop-VMHostService -Confirm:$false -WhatIf:$false | Out-Null
#endRegion