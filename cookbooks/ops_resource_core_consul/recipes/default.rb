#
# Cookbook Name:: ops_resource_core_consul
# Recipe:: default
#
# Copyright 2015, P. van der Velde
#
# All rights reserved - Do Not Redistribute
#

include_recipe 'ops_resource_core_consul::consultemplate'
include_recipe 'ops_resource_core_consul::consul'
include_recipe 'ops_resource_core_consul::consul_config'
include_recipe 'ops_resource_core_consul::consul_health_checks'
include_recipe 'ops_resource_core_consul::consul_as_dns'
