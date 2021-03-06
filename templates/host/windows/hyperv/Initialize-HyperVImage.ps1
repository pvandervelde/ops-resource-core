<#
    .SYNOPSIS

    Connects to the Hyper-V host machine, creates a new Hyper-V virtual machine, pushes all the necessary files up to the
    new Hyper-V virtual machine, executes the Chef cookbook that installs all the required applications and then
    verifies that all the applications have been installed correctly.


    .DESCRIPTION

    The Initialize-HyperVImage script takes all the actions necessary to create and configure a new Hyper-V virtual machine.


    .PARAMETER credential

    The credential that should be used to connect to the remote machine.


    .PARAMETER authenticateWithCredSSP

    A flag that indicates whether remote powershell sessions should be authenticated with the CredSSP mechanism.


    .PARAMETER machineName

    The name of the temporary machine that will be created.


    .PARAMETER osName

    The name of the OS that should be used to create the new VM.


    .PARAMETER hypervHost

    The name of the machine on which the hyper-v server is located.


    .PARAMETER vhdxTemplatePath

    The UNC path to the directory that contains the Hyper-V images.


    .PARAMETER hypervHostVmStoragePath

    The UNC path to the directory that stores the Hyper-V VM information.


    .PARAMETER configPath

    The full path to the directory that contains the unattended file that contains the parameters for an unattended setup
    and any necessary script files which will be used during the configuration of the operating system.


    .PARAMETER staticMacAddress

    An optional static MAC address that is applied to the VM so that it can be given a consistent IP address.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [PSCredential] $credential                                  = $null,

    [Parameter(Mandatory = $false)]
    [switch] $authenticateWithCredSSP,

    [Parameter(Mandatory = $true)]
    [string] $machineName                                       = $(throw 'The machine name for the template machine is required.'),

    [Parameter(Mandatory = $true)]
    [string] $osName                                            = '',

    [Parameter(Mandatory = $true)]
    [string] $hypervHost                                        = '',

    [Parameter(Mandatory = $true)]
    [string] $vhdxTemplatePath                                  = "\\$($hypervHost)\vmtemplates",

    [Parameter(Mandatory = $true)]
    [string] $hypervHostVmStoragePath                           = "\\$(hypervHost)\vms\machines",

    [Parameter(Mandatory = $true)]
    [string] $configPath                                        = '',

    [Parameter(Mandatory = $false)]
    [string] $staticMacAddress                                  = ''
)

Write-Verbose "Initialize-HyperVImage - credential: $credential"
Write-Verbose "Initialize-HyperVImage - authenticateWithCredSSP: $authenticateWithCredSSP"
Write-Verbose "Initialize-HyperVImage - machineName = $machineName"
Write-Verbose "Initialize-HyperVImage - osName = $osName"
Write-Verbose "Initialize-HyperVImage - hypervHost = $hypervHost"
Write-Verbose "Initialize-HyperVImage - vhdxTemplatePath = $vhdxTemplatePath"
Write-Verbose "Initialize-HyperVImage - hypervHostVmStoragePath = $hypervHostVmStoragePath"
Write-Verbose "Initialize-HyperVImage - configPath = $configPath"
Write-Verbose "Initialize-HyperVImage - staticMacAddress = $staticMacAddress"


# Stop everything if there are errors
$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = "Stop"
    }

$startTime = [System.DateTimeOffset]::Now
try
{
    $resourceName = '${ProductName}'
    $resourceVersion = '${VersionSemanticFull}'
    $cookbookNames = '${CookbookNames}'.Split(';')

    $installationDirectory = $(Join-Path $PSScriptRoot 'configuration')
    $testDirectory = $(Join-Path $PSScriptRoot 'verification')
    $logDirectory = $(Join-Path $PSScriptRoot 'logs')

    $installationScript = Join-Path $PSScriptRoot 'New-HypervImage.ps1'
    $verificationScript = Join-Path $PSScriptRoot 'Test-HypervImage.ps1'

    $previewPrefix = "preview_"
    $imageName = "$($resourceName)-$($resourceVersion).vhdx"
    $previewImageName = "$($previewPrefix)$($imageName)"

    & $installationScript `
        -credential $credential `
        -authenticateWithCredSSP:$authenticateWithCredSSP `
        -resourceName $resourceName `
        -resourceVersion $resourceVersion `
        -cookbookNames $cookbookNames `
        -imageName $previewImageName `
        -installationDirectory $installationDirectory `
        -logDirectory $logDirectory `
        -osName $osName `
        -machineName $machineName `
        -hypervHost $hypervHost `
        -vhdxTemplatePath $vhdxTemplatePath `
        -hypervHostVmStoragePath $hypervHostVmStoragePath `
        -configPath $configPath `
        -staticMacAddress $staticMacAddress `
        @commonParameterSwitches

    & $verificationScript `
        -credential $credential `
        -authenticateWithCredSSP:$authenticateWithCredSSP `
        -imageName $previewImageName `
        -testDirectory $testDirectory `
        -logDirectory $logDirectory `
        -machineName $machineName `
        -hypervHost $hypervHost `
        -vhdxTemplatePath $vhdxTemplatePath `
        -hypervHostVmStoragePath $hypervHostVmStoragePath `
        -configPath $configPath `
        -staticMacAddress $staticMacAddress `
        @commonParameterSwitches

    # If the tests pass, then rename the image
    Rename-Item -Path (Join-Path $vhdxTemplatePath $previewImageName) -NewName $imageName -Force @commonParameterSwitches

    # Now make the image file read-only
    Set-ItemProperty -Path (Join-Path $vhdxTemplatePath $imageName) -Name IsReadOnly -Value $true
}
finally
{
    $endTime = [System.DateTimeOffset]::Now
    Write-Output ("Image initialization started: " + $startTime)
    Write-Output ("Image initialization completed: " + $endTime)
    Write-Output ("Total time: " + ($endTime - $startTime))
}
