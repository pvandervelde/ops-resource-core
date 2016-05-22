<#
    .SYNOPSIS

    Verifies that a given Hyper-V image can indeed be used to run the selected resource.


    .DESCRIPTION

    The Test-HyperVImage script verifies that a given image can indeed be used to run the selected resource.


    .PARAMETER credential

    The credential that should be used to connect to the remote machine.


    .PARAMETER authenticateWithCredSSP

    A flag that indicates whether remote powershell sessions should be authenticated with the CredSSP mechanism.


    .PARAMETER resourceName

    The name of the resource that is being created.


    .PARAMETER resourceVersion

    The version of the resource that is being created.


    .PARAMETER cookbookNames

    An array containing the names of the cookbooks that should be executed to install all the required applications on the machine.


    .PARAMETER installationDirectory

    The directory in which all the installer packages and cookbooks can be found. It is expected that the cookbooks are stored
    in a 'cookbooks' sub-directory of the installationDirectory.


    .PARAMETER logDirectory

    The directory in which all the logs should be stored.


    .PARAMETER osName

    The name of the OS that should be used to create the new VM.


    .PARAMETER machineName

    The name of the machine that should be created


    .PARAMETER hypervHost

    The name of the machine on which the hyper-v server is located.


    .PARAMETER vhdxTemplatePath

    The UNC path to the directory that contains the Hyper-V images.


    .PARAMETER hypervHostVmStoragePath

    The UNC path to the directory that stores the Hyper-V VM information.


    .PARAMETER staticMacAddress

    An optional static MAC address that is applied to the VM so that it can be given a consistent IP address.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [PSCredential] $credential                                  = $null,

    [Parameter(Mandatory = $false)]
    [switch] $authenticateWithCredSSP,

    [Parameter(Mandatory = $false)]
    [string] $imageName                                         = "$($resourceName)-$($resourceVersion).vhdx",

    [string] $testDirectory                                     = $(Join-Path $PSScriptRoot "verification"),

    [Parameter(Mandatory = $false)]
    [string] $logDirectory                                      = $(Join-Path $PSScriptRoot 'logs'),

    [Parameter(Mandatory = $true)]
    [string] $machineName                                       = '',

    [Parameter(Mandatory = $true)]
    [string] $hypervHost                                        = '',

    [Parameter(Mandatory = $true)]
    [string] $vhdxTemplatePath                                  = "\\$($hypervHost)\vmtemplates",

    [Parameter(Mandatory = $true)]
    [string] $hypervHostVmStoragePath                           = "\\$($hypervHost)\vms\machines",

    [Parameter(Mandatory = $false)]
    [string] $staticMacAddress                                  = ''
)

Write-Verbose "Test-HyperVImage - credential = $credential"
Write-Verbose "Test-HyperVImage - authenticateWithCredSSP = $authenticateWithCredSSP"
Write-Verbose "Test-HyperVImage - imageName = $imageName"
Write-Verbose "Test-HyperVImage - testDirectory = $testDirectory"
Write-Verbose "Test-HyperVImage - logDirectory = $logDirectory"
Write-Verbose "Test-HyperVImage - machineName = $machineName"
Write-Verbose "Test-HyperVImage - hypervHost = $hypervHost"
Write-Verbose "Test-HyperVImage - vhdxTemplatePath = $vhdxTemplatePath"
Write-Verbose "Test-HyperVImage - hypervHostVmStoragePath = $hypervHostVmStoragePath"
Write-Verbose "Test-HyperVImage - staticMacAddress = $staticMacAddress"

$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = 'Stop'
    }

# Load the helper functions
. (Join-Path $PSScriptRoot consul.ps1)
. (Join-Path $PSScriptRoot hyperv.ps1)
. (Join-Path $PSScriptRoot sessions.ps1)
. (Join-Path $PSScriptRoot WinRM.ps1)

# -------------------- Functions ------------------------

function New-TestConsulConfig
{
    [CmdletBinding()]
    param(
        [string] $datacenter,
        [int] $basePort = 8900,
        [string] $configPath
    )

    Write-Verbose "New-TestConsulConfig - basePort = $basePort"
    Write-Verbose "New-TestConsulConfig - configPath = $configPath"

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = 'Stop'
        }

    $consulConfig = @"
{
  "bootstrap_expect" : 1,
  "server": true,
  "datacenter": "$($datacenter)",

  "ports": {
    "http": $($basePort + 0),
    "dns": $($basePort + 1)
    "rpc": $($basePort + 2),
    "serf_lan": "dns": $($basePort + 3),
    "serf_wan": "dns": $($basePort + 4),
    "server": "dns": $($basePort + 5)
  },

  "dns_config" : {
    "allow_stale" : true,
    "max_stale" : "150s",
    "node_ttl" : "300s",
    "service_ttl": {
      "*": "300s"
    }
  },

  "retry_join_wan": [],
  "retry_interval_wan": "30s",

  "retry_join": [],
  "retry_interval": "30s",

  "recursors": [],

  "disable_remote_exec": true,
  "disable_update_check": true,

  "log_level" : "warn"
}
"@
    $consulConfig | Out-File -FilePath $configPath @commonParameterSwitches
}

# -------------------- Script ---------------------------

if (-not (Test-Path $testDirectory))
{
    throw "Unable to find the directory containing the test files. Expected it at: $testDirectory"
}

if (-not (Test-Path $logDirectory))
{
    New-Item -Path $logDirectory -ItemType Directory | Out-Null
}

if (-not (Test-Path $hypervHostVmStoragePath))
{
    throw "Unable to find the directory where the Hyper-V VMs are stored. Expected it at: $hypervHostVmStoragePath"
}

if (-not (Test-Path $vhdxTemplatePath))
{
    throw "Unable to find the directory where the Hyper-V templates are stored. Expected it at: $vhdxTemplatePath"
}

try
{
    # Configure a consul agent that can be used as the configuration stored
    $datacenter = "TestHyperVImage"
    $basePort = 8950
    $consulConfig = Join-Path $PSScriptRoot 'testconsul_default.json'
    New-TestConsulConfig `
        -datacenter $datacenter `
        -basePort $basePort `
        -configPath $consulConfig `
        @commonParameterSwitches

    $arguments = @(
        "agent",
        "-config-file=$($consulConfig)"
    )
    $consulProcess = Start-Process `
        -FilePath (Join-Path $PSScriptRoot 'consul.exe') `
        -ArgumentList $arguments `
        -WindowStyle Minimized `
        -PassThru `
        @commonParameterSwitches
    try
    {
        $dnsIPAddresses = @(Get-DnsServerIPAddressesFromCurrentMachine @commonParameterSwitches)
        $jsonObject = New-Object psobject -Property @{
            "consul_datacenter" = "TestHyperVImage"
            "consul_recursors" = $dnsIPAddresses
            "consul_lanservers" = ""

            "consul_isserver" = $true
            "consul_numberofservers" = 1
            "consul_domain" = "imagetest"
            "consul_wanservers" = ""
        }

        $consultestconfig = ConvertTo-Json -InputObject $jsonObject @commonParameterSwitches
        $provisioningBootstrapUrl = "http://$($env:COMPUTERNAME):$($basePort)"
        Set-ConsulKeyValue `
            -httpUrl $provisioningBootstrapUrl `
            -dataCenter $datacenter `
            -keyPath "provisioning/$($machineName)/service/consul" `
            -value $consultestconfig `
            @commonParameterSwitches

        $configurationScript = Join-Path $PSScriptRoot 'New-HyperVResource.ps1'
        $connection = & $configurationScript `
            -credential $credential `
            -authenticateWithCredSSP:$authenticateWithCredSSP `
            -imageName $imageName `
            -machineName $machineName `
            -hypervHost $hypervHost `
            -vhdxTemplatePath $vhdxTemplatePath `
            -hypervHostVmStoragePath $hypervHostVmStoragePath `
            -staticMacAddress $staticMacAddress `
            -provisioningBootstrapUrl $provisioningBootstrapUrl `
            @commonParameterSwitches

        Write-Verbose "Connected to $computerName via $($connection.Session.Name)"

        $testWindowsResource = Join-Path $PSScriptRoot 'Test-WindowsResource.ps1'
        & $testWindowsResource -session $connection.Session -testDirectory $testDirectory -logDirectory $logDirectory
    }
    finally
    {
        # Stop consul
        $consulProcess.Kill()
    }
}
finally
{
    # Stop the VM
    try
    {
        Stop-VM `
            -ComputerName $hypervHost `
            -Name $machineName `
            -Force `
            @commonParameterSwitches
    }
    catch
    {
        # just ignore it
    }

    # Delete the VM. If the delete goes wrong we want to know, because we'll have a random VM
    # trying to do stuff on the environment.
    Remove-VM `
        -computerName $hypervHost `
        -Name $machineName `
        -Force `
        @commonParameterSwitches
}