<#
    This file contains the 'unit tests' for the BuildFunctions.Release script. These tests are executed
    using Pester (https://github.com/pester/Pester).
#>

Describe 'Consul installation' {

    Context 'The consul install location' {
        It 'has the directories' {
            'c:\ops' | Should Exist
            'c:\ops\consul' | Should Exist
            'c:\ops\consul\bin' | Should Exist
            'c:\ops\consul\data' | Should Exist
        }

        It 'has the metadata transfer script' {
            'c:\ops\consul\Set-ConsulMetadata.ps1' | Should Exist
        }

        It 'has the Consul binaries' {
            'c:\ops\consul\bin\consul_service.exe' | Should Exist
            'c:\ops\consul\bin\consul_service.xml' | Should Exist
            'c:\ops\consul\bin\consul_service.exe.config' | Should Exist
            'c:\ops\consul\bin\consul.exe' | Should Exist
        }

        It 'has a valid default consul configuration file' {
            $consulConfiguration = 'c:\ops\consul\bin\consul_default.json'
            $consulConfiguration | Should Exist
            { ConvertFrom-Json (Get-Content $consulConfiguration) } | Should Not Throw
        }
    }

    Context 'The meta install location' {
        It 'has the directories' {
            'c:\meta' | Should Exist
            'c:\meta\consul' | Should Exist
            'c:\meta\consul\checks' | Should Exist
        }

        It 'has the Consul checks' {
            'c:\meta\consul\checks\Test-Disk.ps1' | Should Exist
            'c:\meta\consul\checks\Test-Load.ps1' | Should Exist
            'c:\meta\consul\checks\Test-Memory.ps1' | Should Exist
        }

        It 'has a valid check_server file' {
            $checkServer = 'c:/meta/consul/check_server.json'
            $checkServer | Should Exist
            { ConvertFrom-Json (Get-Content $checkServer) } | Should Not Throw
        }
    }

    Context 'The consul service' {
        $service = Get-WmiObject win32_service | Where {$_.name -eq 'consul'} | Select -First 1
        It 'is running as consul_user' {
            $service | Should Not BeNullOrEmpty
            $service.StartName | Should Be 'consul_user'
        }

        It 'starts automatically' {
            $service.StartMode | Should Be 'Auto'
        }

        It 'responds to queries' {
            $service.Started | Should Be 'True'

            $response = Invoke-WebRequest -Uri 'http://localhost:8500/v1/agent/self'
            $json = ConvertFrom-Json -InputObject $consulHttpResponse
            $consulHttp = ConvertFrom-ConsulEncodedValue -encodedValue $json.Value
            $consulHttp.Config.Version | Should Be '0.5.0'
        }
    }
}
