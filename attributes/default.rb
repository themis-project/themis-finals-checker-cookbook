id = 'themis-finals-checker'

default[id]['fqdn'] = nil

default[id]['service_alias'] = nil

default[id]['deployment']['instances'] = 2
default[id]['deployment']['port_range_start'] = 5001
default[id]['deployment']['env'] = {}

default[id]['image']['name'] = nil
default[id]['image']['registry'] = nil
default[id]['image']['repo'] = nil
default[id]['image']['tag'] = 'latest'

default[id]['network']['name'] = nil
default[id]['network']['subnet'] = '192.168.163.0/24'
default[id]['network']['gateway'] = '192.168.163.1'
