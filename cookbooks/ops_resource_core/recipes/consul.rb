#
# Cookbook Name:: ops_resource_core
# Recipe:: consul
#
# Copyright 2015, P. van der Velde
#
# All rights reserved - Do Not Redistribute
#

include_recipe 'windows'
include_recipe 'windows_firewall'

log_directory = 'c:/logs'

service_name = 'consul'
win_service_name = 'consul_service'

# Create user
# - limited user
# - Reduce access to files. User should only have write access to consul dir
consul_username = 'consul_user'
consul_password = SecureRandom.uuid
user consul_username do
  password consul_password
  action :create
end

# Grant the user the LogOnAsService permission. Following this anwer on SO: http://stackoverflow.com/a/21235462/539846
# With some additional bug fixes to get the correct line from the export file and to put the correct text in the import file
powershell_script 'user_grant_service_logon_rights' do
  code <<-POWERSHELL
    $ErrorActionPreference = 'Stop'

    $userName = "#{consul_username}"

    $tempPath = "#{log_directory}"
    $import = Join-Path -Path $tempPath -ChildPath "import.inf"
    if(Test-Path $import)
    {
        Remove-Item -Path $import -Force
    }

    $export = Join-Path -Path $tempPath -ChildPath "export.inf"
    if(Test-Path $export)
    {
        Remove-Item -Path $export -Force
    }

    $secedt = Join-Path -Path $tempPath -ChildPath "secedt.sdb"
    if(Test-Path $secedt)
    {
        Remove-Item -Path $secedt -Force
    }

    Write-Host ("Granting SeServiceLogonRight to user account: {0} on host: {1}." -f $userName, $computerName)
    $sid = ((New-Object System.Security.Principal.NTAccount($userName)).Translate([System.Security.Principal.SecurityIdentifier])).Value

    secedit /export /cfg $export
    $line = (Select-String $export -Pattern "SeServiceLogonRight").Line
    $sids = $line.Substring($line.IndexOf('=') + 1).Trim()

    $lines = @(
            "[Unicode]",
            "Unicode=yes",
            "[System Access]",
            "[Event Audit]",
            "[Registry Values]",
            "[Version]",
            "signature=`"`$CHICAGO$`"",
            "Revision=1",
            "[Profile Description]",
            "Description=GrantLogOnAsAService security template",
            "[Privilege Rights]",
            "SeServiceLogonRight = $sids,*$sid"
        )
    foreach ($line in $lines)
    {
        Add-Content $import $line
    }

    secedit /import /db $secedt /cfg $import
    secedit /configure /db $secedt
    gpupdate /force
  POWERSHELL
end

consul_data_directory = node['paths']['consul_data']
directory consul_data_directory do
  rights :read, 'Everyone', applies_to_children: true, applies_to_self: false
  rights :modify, consul_username, applies_to_children: true, applies_to_self: false
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

consul_checks_directory = node['paths']['consul_checks']
directory consul_checks_directory do
  rights :read, 'Everyone', applies_to_children: true, applies_to_self: false
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

consul_bin_directory = node['paths']['consul_bin']
directory consul_bin_directory do
  rights :read_execute, 'Everyone', applies_to_children: true, applies_to_self: false
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

consul_exe = 'consul.exe'
cookbook_file "#{consul_bin_directory}\\#{consul_exe}" do
  source consul_exe
  action :create
end

# add the winsw binaries
# Copy the service runner & rename to consul.exe
cookbook_file "#{consul_bin_directory}\\#{win_service_name}.exe" do
  source 'winsw-1.16-bin.exe'
  action :create
end

file "#{consul_bin_directory}\\#{win_service_name}.exe.config" do
  content <<-XML
<configuration>
    <runtime>
        <generatePublisherEvidence enabled="false"/>
    </runtime>
    <startup>
        <supportedRuntime version="v4.0" />
        <supportedRuntime version="v2.0.50727" />
    </startup>
</configuration>
  XML
  action :create
end

# Get IP for consul join from CMDB
consul_config_directory = node['paths']['consul_config']
ip_consul_entry_node = node['consul']['entry_node_ip']

file "#{consul_bin_directory}\\#{win_service_name}.xml" do
  content <<-XML
<?xml version="1.0"?>
<!--
    The MIT License Copyright (c) 2004-2009, Sun Microsystems, Inc., Kohsuke Kawaguchi Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
    PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-->

<service>
    <id>#{service_name}</id>
    <name>#{service_name}</name>
    <description>This service runs the consul agent.</description>

    <executable>#{consul_bin_directory}\\consul.exe</executable>
    <arguments>agent -data-dir #{consul_data_directory} -config-dir #{consul_config_directory} -retry-join=#{ip_consul_entry_node} -retry-interval=30s</arguments>

    <!-- interactive flag causes the empty black Java window to be displayed. I'm still debugging this. <interactive /> -->
    <logmode>rotate</logmode>
    <onfailure action="restart"/>
</service>
    XML
  action :create
end

# Install consul_service.exe as service
powershell_script 'consul_as_service' do
  code <<-POWERSHELL
    $ErrorActionPreference = 'Stop'

    Write-Host "ConsulUser: #{consul_username}"
    Write-Host "ConsulPassword: #{consul_password}"

    $securePassword = ConvertTo-SecureString "#{consul_password}" -AsPlainText -Force

    # Note the .\\ is to get the local machine account as per here:
    # http://stackoverflow.com/questions/313622/powershell-script-to-change-service-account#comment14535084_315616
    $credential = New-Object pscredential((".\\" + "#{consul_username}"), $securePassword)

    New-Service -Name '#{service_name}' -BinaryPathName '#{consul_bin_directory}\\#{win_service_name}.exe' -Credential $credential -DisplayName '#{service_name}' -StartupType Automatic
  POWERSHELL
end

# Create the event log source for the jenkins service. We'll create it now because the service runs as a normal user
# and is as such not allowed to create eventlog sources
registry_key "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}" do
  values [{
    name: 'EventMessageFile',
    type: :string,
    data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll'
  }]
  action :create
end

meta_directory = node['paths']['meta']
directory meta_directory do
  rights :read, 'Everyone', applies_to_children: true, applies_to_self: false
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

# Add file to meta directory containing information about consul install
file "#{meta_directory}\\service_consul.json" do
  content <<-JSON
{
    "install_path": "#{consul_bin_directory}",
    "config_path": "#{consul_config_directory}",
}
  JSON
  action :create
end

# windows_firewall_rule 'Consul_Tcp' do
#   protocol :TCP
#   firewall_action :allow
# end
shell_out("netsh advfirewall firewall add rule name=\"Consul_Tcp\" dir=in action=allow protocol=TCP program=\"#{consul_bin_directory}\\consul.exe\" enable=yes profile=domain")

# windows_firewall_rule 'Consul' do
#   protocol :UDP
#   firewall_action :allow
# end
shell_out("netsh advfirewall firewall add rule name=\"Consul_UDP\" dir=in action=allow protocol=UDP program=\"#{consul_bin_directory}\\consul.exe\" enable=yes profile=domain")

consul_base_path = node['paths']['consul_base']
set_consul_metadata = 'Set-ConsulMetadata.ps1'
cookbook_file "#{consul_base_path}\\#{set_consul_metadata}" do
  source set_consul_metadata
  action :create
end

# upon reboot connect to the join node and set the meta data for the current resource to be equal to the data in the meta.json file
registry_key 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce' do
  values [{
    name: 'SetResourceMetadataInConsul',
    type: :string,
    data: "powershell.exe -NoProfile -NonInteractive -NoLogo -File #{consul_base_path}\\#{set_consul_metadata} -metaFile #{meta_directory}\\meta.json -consulServiceName #{service_name}"
  }]
  action :create
end
