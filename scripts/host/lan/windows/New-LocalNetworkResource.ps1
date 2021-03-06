<#
    .SYNOPSIS

    Connects to the remote machine, pushes all the necessary files up to it and then executes the Chef cookbook that installs
    all the required applications.


    .DESCRIPTION

    The New-WindowsResource script takes all the actions necessary to configure the machine.


    .PARAMETER credential

    The credential that should be used to connect to the remote machine.


    .PARAMETER authenticateWithCredSSP

    A flag that indicates whether remote powershell sessions should be authenticated with the CredSSP mechanism.


    .PARAMETER computerName

    The name of the machine that should be set up.


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


    .EXAMPLE

    New-WindowsResource -computerName "MyMachine" -installationDirectory "c:\installers" -logDirectory "c:\logs"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [PSCredential] $credential                                  = $null,

    [Parameter(Mandatory = $false)]
    [switch] $authenticateWithCredSSP,

    [Parameter(Mandatory = $true)]
    [string] $computerName                                      = $(throw 'Please specify the name of the machine that should be configured.'),

    [Parameter(Mandatory = $false)]
    [string] $resourceName                                      = '',

    [Parameter(Mandatory = $false)]
    [string] $resourceVersion                                   = '',

    [Parameter(Mandatory = $true)]
    [string[]] $cookbookNames                                   = $(throw 'Please specify the names of the cookbooks that should be executed.'),

    [Parameter(Mandatory = $false)]
    [string] $installationDirectory                             = $(Join-Path $PSScriptRoot 'configuration'),

    [Parameter(Mandatory = $false)]
    [string] $logDirectory                                      = $(Join-Path $PSScriptRoot 'logs')
)

Write-Verbose "New-LocalNetworkResource - credential: $credential"
Write-Verbose "New-LocalNetworkResource - authenticateWithCredSSP: $authenticateWithCredSSP"
Write-Verbose "New-LocalNetworkResource - computerName: $computerName"
Write-Verbose "New-LocalNetworkResource - resourceName: $resourceName"
Write-Verbose "New-LocalNetworkResource - resourceVersion: $resourceVersion"
Write-Verbose "New-LocalNetworkResource - cookbookNames: $cookbookNames"
Write-Verbose "New-LocalNetworkResource - installationDirectory: $installationDirectory"
Write-Verbose "New-LocalNetworkResource - logDirectory: $logDirectory"

# Stop everything if there are errors
$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = 'Stop'
    }

# Load the helper functions
. (Join-Path $PSScriptRoot sessions.ps1)

if (-not (Test-Path $installationDirectory))
{
    throw "Unable to find the directory containing the installation files. Expected it at: $installationDirectory"
}

if (-not (Test-Path $logDirectory))
{
    New-Item -Path $logDirectory -ItemType Directory | Out-Null
}

$session = New-Session -computerName $computerName -credential $credential -authenticateWithCredSSP:$authenticateWithCredSSP @commonParameterSwitches
if ($session -eq $null)
{
    throw "Failed to connect to $computerName"
}

$newWindowsResource = Join-Path $PSScriptRoot 'New-WindowsResource.ps1'
& $newWindowsResource `
    -session $session `
    -resourceName $resourceName `
    -resourceVersion $resourceVersion `
    -cookbookNames $cookbookNames `
    -installationDirectory $installationDirectory `
    -logDirectory $logDirectory `
    @commonParameterSwitches
