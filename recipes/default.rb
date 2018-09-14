id = 'themis-finals-checker'

instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

docker_service 'default' do
  action [:create, :start]
end

docker_network node[id]['network']['name'] do
  subnet node[id]['network']['subnet']
  gateway node[id]['network']['gateway']
end

repo_name = node[id]['image']['repo']

unless node[id]['image']['registry'].nil?
  registry_addr = "#{node[id]['image']['registry']}"
  registry_port = secret.get("docker:#{node[id]['image']['registry']}:port", default: 443)
  unless registry_port == 443
    registry_addr += ":#{registry_port}"
  end

  docker_registry node[id]['image']['registry'] do
     serveraddress "https://#{registry_addr}/"
     username secret.get("docker:#{node[id]['image']['registry']}:username")
     password secret.get("docker:#{node[id]['image']['registry']}:password")
  end

  repo_name = registry_addr + "/#{repo_name}"
end

docker_image node[id]['image']['name'] do
  repo repo_name
  tag node[id]['image']['tag']
  action :pull
end

base_dir = '/opt/themis/finals'

directory base_dir do
  owner instance.root
  group node['root_group']
  mode 0755
  recursive true
  action :create
end

dotenv_file = ::File.join(base_dir, '.env')

template dotenv_file do
  source 'dotenv.erb'
  user instance.root
  group node['root_group']
  mode 0600
  variables(
    env: node[id]['deployment']['env'].to_hash.merge({
      'THEMIS_FINALS_AUTH_MASTER_USERNAME' => secret.get('themis-finals:auth:master:username'),
      'THEMIS_FINALS_AUTH_MASTER_PASSWORD' => secret.get('themis-finals:auth:master:password'),
      'THEMIS_FINALS_AUTH_CHECKER_USERNAME' => secret.get('themis-finals:auth:checker:username'),
      'THEMIS_FINALS_AUTH_CHECKER_PASSWORD' => secret.get('themis-finals:auth:checker:password'),
      'THEMIS_FINALS_FLAG_SIGN_KEY_PUBLIC' => secret.get('themis-finals:sign_key:public').gsub("\n", "\\n"),
      'THEMIS_FINALS_FLAG_WRAP_PREFIX' => node['themis-finals']['flag_wrap']['prefix'],
      'THEMIS_FINALS_FLAG_WRAP_SUFFIX' => node['themis-finals']['flag_wrap']['suffix']
    })
  )
  action :create
end

systemd_unit "#{node[id]['image']['name']}@.service" do
  content({
    Unit: {
      Description: "#{node[id]['image']['name']} container on port %i",
      Requires: 'docker.service',
      After: 'docker.service'
    },
    Service: {
      Restart: 'always',
      RestartSec: 5,
      ExecStartPre: %Q(/bin/sh -c "/usr/bin/docker rm -f #{node[id]['image']['name']}-%i 2> /dev/null || /bin/true"),
      ExecStart: "/usr/bin/docker run --rm -a STDIN -a STDOUT -a STDERR -p 127.0.0.1:%i:80 --network #{node[id]['network']['name']} --env-file #{dotenv_file} --name #{node[id]['image']['name']}-%i #{repo_name}:#{node[id]['image']['tag']}",
      ExecStop: "/usr/bin/docker stop #{node[id]['image']['name']}-%i"
    },
    Install: {
      WantedBy: 'multi-user.target'
    }
  })
  action :create
end

::Range.new(0, node[id]['deployment']['instances'] - 1).each do |num|
  port = node[id]['deployment']['port_range_start'] + num
  service "#{node[id]['image']['name']}@#{port}" do
    action [:enable, :start]
  end
end

ngx_vhost = "themis-finals-checker-#{node[id]['service_alias']}"

nginx_site ngx_vhost do
  template 'nginx.conf.erb'
  variables(
    server_name: node[id]['fqdn'] || instance.fqdn,
    service_name: node[id]['service_alias'],
    debug: node[id]['debug'],
    access_log: ::File.join(node['nginx']['log_dir'], "#{ngx_vhost}_access.log"),
    error_log: ::File.join(node['nginx']['log_dir'], "#{ngx_vhost}_error.log"),
    upstream_instances: node[id]['deployment']['instances'],
    upstream_port_range_start: node[id]['deployment']['port_range_start'],
    internal_networks: node['themis-finals']['config']['internal_networks']
  )
  action :enable
end
