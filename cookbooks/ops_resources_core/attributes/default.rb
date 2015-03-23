meta_base_path = 'c:\\meta'
default['paths']['meta'] = meta_base_path

consul_base_path = 'c:\\ops\\consul'
default['paths']['consul_bin'] = "#{consul_base_path}\\bin"
default['paths']['consul_data'] = "#{consul_base_path}\\data"
default['paths']['consul_checks'] = "#{consul_base_path}\\checks"
default['paths']['consul_config'] = "#{meta_base_path}\\consul"

# Install 7-zip
default['7-zip']['url'] = 'http://downloads.sourceforge.net/project/sevenzip/7-Zip/9.36/7z936-x64.msi'
default['7-zip']['package_name'] = '7-Zip 9.36 (x64 edition)'
