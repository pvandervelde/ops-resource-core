#
# Cookbook Name:: ops_resource_core
# Recipe:: consul_health_checks
#
# Copyright 2015, P. van der Velde
#
# All rights reserved - Do Not Redistribute
#

# Add health check scripts
consul_checks_directory = node['paths']['consul_checks']
test_disk = 'Test-Disk.ps1'
cookbook_file "#{consul_checks_directory}\\#{test_disk}" do
  source test_disk
  action :create
end

test_memory = 'Test-Memory.ps1'
cookbook_file "#{consul_checks_directory}\\#{test_memory}" do
  source test_memory
  action :create
end

test_load = 'Test-Load.ps1'
cookbook_file "#{consul_checks_directory}\\#{test_load}" do
  source test_load
  action :create
end

consul_config_directory = node['paths']['consul_config']
# We need to multiple-escape the escape character because of ruby string and regex etc. etc. See here: http://stackoverflow.com/a/6209532/539846
consul_checks_directory_json_escaped = consul_checks_directory.gsub('\\', '\\\\\\\\')
file "#{consul_config_directory}\\check_server.json" do
  content <<-JSON
{
    "service":
    {
        "name": "NodeMeta",
        "id": "node_meta",
        "tags":
        [
            "Windows"
        ]
    },
    "checks": [
        {
            "id": "disk",
            "name": "Disk",
            "script": "powershell.exe -NoProfile -NonInteractive -NoLogo -InputFormat Text -OutputFormat Text -File #{consul_checks_directory_json_escaped}\\\\#{test_disk}",
            "interval": "60s",
            "notes": "Critical 5% free, warning 10% free"
        },
        {
            "id": "memory",
            "name": "Memory",
            "script": "powershell.exe -NoProfile -NonInteractive -NoLogo -InputFormat Text -OutputFormat Text -File #{consul_checks_directory_json_escaped}\\\\#{test_memory}",
            "interval": "60s",
            "notes": "Critical 5% free, warning 10% free"
        },
        {
            "id": "load",
            "name": "Load",
            "script": "powershell.exe -NoProfile -NonInteractive -NoLogo -InputFormat Text -OutputFormat Text -File #{consul_checks_directory_json_escaped}\\\\#{test_load}",
            "interval": "60s",
            "notes": "Critical 95%, warning 90%"
        }
    ]
}
  JSON
  action :create
end
