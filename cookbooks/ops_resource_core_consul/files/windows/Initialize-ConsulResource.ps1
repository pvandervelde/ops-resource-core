[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = "Stop"
    }

# -------------------------- Script classes --------------------------------

class ConsulProvisioner
{
    [hashtable] $commonParameterSwitches

    ConsulProvisioner ([hashtable] $commonParameterSwitches)
    {
        $this.commonParameterSwitches = $commonParameterSwitches
    }

    [string[]] Dependencies()
    {
        return @( 'Meta', 'Provisioning' )
    }

    [void] EnableAndStartService([string] $serviceName)
    {
        Set-Service `
            -Name $serviceName `
            -StartupType Automatic `
            @($this.commonParameterSwitches)

        $service = Get-Service -Name $serviceName @($this.commonParameterSwitches)
        if ($service.Status -ne 'Running')
        {
            Start-Service -Name $serviceName @($this.commonParameterSwitches)
        }
    }

    [psobject] GetServiceMetadata([string] $serviceName)
    {
        $configPath = "c:\meta\service_$($serviceName).json"
        $json = ConvertFrom-Json -InputObject (Get-Content -Path $configPath)  @($this.commonParameterSwitches)

        return $json
    }

    [string] MachineIp()
    {
        $result = ''
        $adapters = Get-NetAdapter @($this.commonParameterSwitches)
        foreach($adapter in $adapters)
        {
            if ($adapter.Status -ne 'Up')
            {
                continue
            }

            $address = Get-NetIPAddress -InterfaceAlias $adapter.InterfaceAlias |
                Where-Object { $_.AddressFamily -ne 'IPv6' }

            if (($address -ne $null) -and ($address -ne ''))
            {
                $result = $address.IPAddress
                break
            }
        }

        return $result
    }

    [void] Provision([psobject] $configuration)
    {
        $this.ProvisionConsul($configuration)
        $this.ProvisionConsulTemplate($configuration)
    }

    [void] ProvisionConsul([psobject] $configuration)
    {
        $meta = $this.GetServiceMetadata('consul')
        $json = ConvertFrom-Json -InputObject (Get-Content -Path $meta.service.application_config)  @($this.commonParameterSwitches)
        $json.datacenter = $configuration.consul_datacenter
        $json.recursors = $configuration.consul_recursors
        $json.retry_join = $configuration.consul_lanservers

        if ($configuration.consul_isserver)
        {
            $json.bootstrap_expect = $configuration.consul_numberofservers
            $json.server = $true
            $json.domain = $configuration.consul_domain

            $addresses = New-Object psobject -Property @{
                dns = $this.MachineIp()
            }
            $json.addresses = $addresses

            $json.retry_join_wan = $configuration.consul_wanservers
        }

        $textContent = ConvertTo-Json -InputObject $json
        Out-File -FilePath $meta.service.application_config -InputObject $textContent -Force -NoNewline @($this.commonParameterSwitches)

        $this.EnableAndStartService($meta.service.win_service)
    }

    [void] ProvisionConsulTemplate([psobject] $configuration)
    {
        $metaConsul = $this.GetServiceMetadata('consul')
        $metaConsulTemplate = $this.GetServiceMetadata('consultemplate')

        # overwrite some of the values with consul template parameters
        $textContent = Get-Content -Path $metaConsul.service.application_config
        $lines = $textContent.Split([System.Environment]::NewLine)
        for($i = 0; $i -lt $lines.Length; $i++)
        {
            $currentLine = $lines[$i]

            # Replace the values in the following sections in the consul config with the consultemplate parameters
            switch -Regex ($currentLine)
            {
                # "dns_config" : {
                #    "allow_stale" : true,
                #},
                '("allow_stale")(\s)?(:)(\s)?(\")' {
                    $lines[$i] = "`"allow_stale`" : {{key `"resource/$($env:COMPUTERNAME)/service/consul/config/dns/allowstale`"}},"
                }

                # "dns_config" : {
                #    "max_stale" : "30s",
                #},
                '("max_stale")(\s)?(:)(\s)?(\")' {
                    $lines[$i] = "`"max_stale`" : `"{{key `"resource/$($env:COMPUTERNAME)/service/consul/config/dns/maxstale`"}}`","
                }

                # "dns_config" : {
                #    "node_ttl" : "60s",
                #},
                '("node_ttl")(\s)?(:)(\s)?(\")' {
                    $lines[$i] = "`"node_ttl`" : `"{{key `"resource/$($env:COMPUTERNAME)/service/consul/config/dns/nodettl`"}}`","
                }

                # "dns_config" : {
                #        "service_ttl": {
                #        "*": "120s"
                #        }
                #    },
                '("\*")(\s)?(:)(\s)?(\")' {
                    $lines[$i] = "`"*`": `"{{key `"resource/$($env:COMPUTERNAME)/service/consul/config/dns/servicettl`"}}`""
                }

                # "log_level" : "debug"
                '("log_level")(\s)?(:)(\s)?(\")' {
                    $lines[$i] = "`"log_level`" : `"{{key `"resource/$($env:COMPUTERNAME)/service/consul/config/loglevel`"}}`""
                }
            }
        }

        Out-File -FilePath $metaConsulTemplate.Service.template_path -InputObject $lines -Force -NoNewline @($this.commonParameterSwitches)

        # Make sure the service starts automatically when the machine starts, and then start the service if required
        $this.EnableAndStartService($metaConsulTemplate.service.win_service)
    }

    [string] ResourceName()
    {
        return 'Consul'
    }
}

# -------------------------- Script start ------------------------------------

[ConsulProvisioner]::New($commonParameterSwitches)