meta_base_path = 'c:\\meta'
default['paths']['meta'] = meta_base_path

consul_base_path = 'c:\\ops\\consul'
default['paths']['consul_bin'] = "#{consul_base_path}\\bin"
default['paths']['consul_data'] = "#{consul_base_path}\\data"
default['paths']['consul_checks'] = "#{consul_base_path}\\checks"
default['paths']['consul_config'] = "#{meta_base_path}\\consul"
