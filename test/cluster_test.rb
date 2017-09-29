require_relative 'helper'

# ruby -w -Itest test/cluster_test.rb
class TestCluster < Test::Unit::TestCase
  include Helper::Cluster

  def test_extract_hash_tag
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal 'user1000', @r.send(:extract_hash_tag, '{user1000}.following')
    assert_equal 'user1000', @r.send(:extract_hash_tag, '{user1000}.followers')
    assert_equal '', @r.send(:extract_hash_tag, 'foo{}{bar}')
    assert_equal '{bar', @r.send(:extract_hash_tag, 'foo{{bar}}zap')
    assert_equal 'bar', @r.send(:extract_hash_tag, 'foo{bar}{zap}')
  end

  def test_cluster_slots
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal 3, @r.cluster('slots').length
    assert_equal true, @r.cluster('slots').first.key?(:start_slot)
    assert_equal true, @r.cluster('slots').first.key?(:end_slot)
    assert_equal true, @r.cluster('slots').first.key?(:master)
    assert_equal true, @r.cluster('slots').first.fetch(:master).key?(:ip)
    assert_equal true, @r.cluster('slots').first.fetch(:master).key?(:port)
    assert_equal true, @r.cluster('slots').first.fetch(:master).key?(:node_id)
    assert_equal true, @r.cluster('slots').first.key?(:replicas)
    assert_equal true, @r.cluster('slots').first.fetch(:replicas).is_a?(Array)
    assert_equal true, @r.cluster('slots').first.fetch(:replicas).first.key?(:ip)
    assert_equal true, @r.cluster('slots').first.fetch(:replicas).first.key?(:port)
    assert_equal true, @r.cluster('slots').first.fetch(:replicas).first.key?(:node_id)
  end

  def test_cluster_keyslot
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal Redis::Cluster::KeySlotConverter.convert('hogehoge'), @r.cluster('keyslot', 'hogehoge')
    assert_equal Redis::Cluster::KeySlotConverter.convert('12345'), @r.cluster('keyslot', '12345')
    assert_equal Redis::Cluster::KeySlotConverter.convert('foo'), @r.cluster('keyslot', 'boo{foo}woo')
    assert_equal Redis::Cluster::KeySlotConverter.convert('antirez.is.cool'), @r.cluster('keyslot', 'antirez.is.cool')
  end

  def test_cluster_nodes
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal 6, @r.cluster('nodes').length
    assert_equal true, @r.cluster('nodes').first.key?(:node_id)
    assert_equal true, @r.cluster('nodes').first.key?(:ip_port)
    assert_equal true, @r.cluster('nodes').first.key?(:flags)
    assert_equal true, @r.cluster('nodes').first.key?(:master_node_id)
    assert_equal true, @r.cluster('nodes').first.key?(:ping_sent)
    assert_equal true, @r.cluster('nodes').first.key?(:pong_recv)
    assert_equal true, @r.cluster('nodes').first.key?(:config_epoch)
    assert_equal true, @r.cluster('nodes').first.key?(:link_state)
    assert_equal true, @r.cluster('nodes').first.key?(:slots)
  end

  def test_cluster_slaves
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    sample_master_node_id = @r.cluster('nodes').find { |n| n.fetch(:master_node_id) == '-' }.fetch(:node_id)
    assert_equal 'slave', @r.cluster('slaves', sample_master_node_id).first.fetch(:flags).first
  end

  def test_cluster_info
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal '3', @r.cluster('info').fetch(:cluster_size)
  end

  def test_well_known_commands_work
    nodes = ['redis://127.0.0.1:7000',
             'redis://127.0.0.1:7001',
             { host: '127.0.0.1', port: '7002' },
             { 'host' => '127.0.0.1', port: 7003 },
             'redis://127.0.0.1:7004',
             'redis://127.0.0.1:7005']

    @r = Redis::Cluster.new(nodes)

    100.times { |i| @r.set(i.to_s, "hogehoge#{i}") }
    100.times { |i| assert_equal "hogehoge#{i}", @r.get(i.to_s) }
    assert_equal '1', @r.info['cluster_enabled']
  end

  def test_client_respond_to_commands
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_equal true, @r.respond_to?(:set)
    assert_equal true, @r.respond_to?('set')
    assert_equal true, @r.respond_to?(:get)
    assert_equal true, @r.respond_to?('get')
    assert_equal false, @r.respond_to?(:unknown_method)
  end

  def test_unknown_command_does_not_work
    nodes = (7000..7005).map { |port| "redis://127.0.0.1:#{port}" }

    @r = Redis::Cluster.new(nodes)

    assert_raise(NoMethodError) do
      @r.not_yet_implemented_command('boo', 'foo')
    end
  end

  def test_client_does_not_accept_db_specified_url
    nodes = ['redis://127.0.0.1:7000/1/namespace']

    assert_raise(Redis::CommandError, 'ERR SELECT is not allowed in cluster mode') do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_unconnectable_node_url_only
    nodes = ['redis://127.0.0.1:7006']

    assert_raise(Redis::CannotConnectError, 'Could not connect to any nodes') do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_accept_unconnectable_node_url_included
    nodes = ['redis://127.0.0.1:7000', 'redis://127.0.0.1:7006']

    assert_nothing_raised(Redis::CannotConnectError, 'Could not connect to any nodes') do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_http_scheme_url
    nodes = ['http://127.0.0.1:80']

    assert_raise(ArgumentError, "invalid uri scheme 'http'") do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_blank_included_config
    nodes = ['']

    assert_raise(ArgumentError, "invalid uri scheme ''") do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_bool_included_config
    nodes = [true]

    assert_raise(ArgumentError, "invalid uri scheme ''") do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_nil_included_config
    nodes = [nil]

    assert_raise(ArgumentError, "invalid uri scheme ''") do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_array_included_config
    nodes = [[]]

    assert_raise(ArgumentError, "invalid uri scheme ''") do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_empty_hash_included_config
    nodes = [{}]

    assert_raise(KeyError, 'key not found: :host') do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_object_included_config
    nodes = [Object.new]

    assert_raise(ArgumentError, 'Redis Cluster node config must includes String or Hash') do
      @r = Redis::Cluster.new(nodes)
    end
  end

  def test_client_does_not_accept_not_array_config
    nodes = :not_array

    assert_raise(ArgumentError, 'Redis Cluster node config must be Array') do
      @r = Redis::Cluster.new(nodes)
    end
  end
end
