class elasticsearch::customer {
  class { 'elasticsearch' :
    config     => {
      'node'   => {
        'name' => 'elasticsearch1'
      },
      'index'                => {
        'number_of_replicas' => '1',
        'number_of_shards'   => '5'
      },
      'network' => {
        'host'  => '127.0.0.1'
      }
    },
    service_settings => {
      'ES_USER'      => 'elasticsearch',
      'ES_GROUP'     => 'elasticsearch',
      'ES_HEAP_SIZE' => '2g',
    }
  }
}
