require 'chefspec'

RSpec.configure do |config|
  # Specify the path for Chef Solo to find cookbooks (default: [inferred from
  # the location of the calling spec file])
  # config.cookbook_path = File.join(File.dirname(__FILE__), '..', '..')

  # Specify the path for Chef Solo to find roles (default: [ascending search])
  # config.role_path = '/var/roles'

  # Specify the path for Chef Solo to find environments (default: [ascending search])
  # config.environment_path = '/var/environments'

  # Specify the Chef log_level (default: :warn)
  config.log_level = :debug

  # Specify the path to a local JSON file with Ohai data (default: nil)
  # config.path = 'ohai.json'

  # Specify the operating platform to mock Ohai data from (default: nil)
  config.platform = 'windows'

  # Specify the operating version to mock Ohai data from (default: nil)
  config.version = '2012'
end

describe 'ops_resource_core_consul::consul_health_checks' do
  let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

  it 'copies the Test-Disk.ps1 file' do
    expect(chef_run).to create_cookbook_file('c:\\meta\\consul\\checks\\Test-Disk.ps1').with(source: 'Test-Disk.ps1')
  end

  consul_checks_directory_json_escaped = 'c:\\\\meta\\\\consul\\\\checks'
  check_server_content = <<-JSON
{
    "service":
    {
        "name": "nodemeta",
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
            "script": "powershell.exe -NoProfile -NonInteractive -NoLogo -InputFormat Text -OutputFormat Text -File #{consul_checks_directory_json_escaped}\\\\Test-Disk.ps1",
            "interval": "60s",
            "notes": "Critical 5% free, warning 10% free",
            "service_id" : "node_meta"
        }
    ]
}
  JSON
  it 'creates the health check configuration file' do
    expect(chef_run).to create_file('c:\\meta\\consul\\check_server.json').with_content(check_server_content)
  end
end
