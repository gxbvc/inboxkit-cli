#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'socket'
require 'json'
require 'stringio'

load File.expand_path('../inboxkit-cli', __dir__)

# Stubs API_URL so api_req hits our TCPServer instead of the real InboxKit API.
class StubServer
  attr_reader :requests

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @responses = []
    @requests = []
    @thread = Thread.new { loop { serve_one } }
  end

  def queue_response(status, body)
    @responses << [status, body]
  end

  def url
    "http://127.0.0.1:#{@server.addr[1]}"
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def serve_one
    client = @server.accept
    request_line = client.gets
    method, path, = request_line.split(' ')
    headers = {}
    while (line = client.gets) && line != "\r\n"
      k, v = line.split(':', 2)
      headers[k.strip] = v.strip
    end
    body = ''
    if headers['Content-Length']
      body = client.read(headers['Content-Length'].to_i)
    end
    @requests << { method: method, path: path, headers: headers, body: body }

    status, resp_body = @responses.shift || [200, '{}']
    client.print "HTTP/1.1 #{status} OK\r\n"
    client.print "Content-Type: application/json\r\n"
    client.print "Content-Length: #{resp_body.bytesize}\r\n"
    client.print "\r\n"
    client.print resp_body
    client.close
  rescue IOError, Errno::EBADF
    nil
  end
end

class InboxkitCliTest < Minitest::Test
  def setup
    @server = StubServer.new
    Object.send(:remove_const, :API_URL)
    Object.const_set(:API_URL, @server.url)
    @cfg = { key: 'test-key', workspace: 'ws-123' }
  end

  def teardown
    @server.stop
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  def test_account_table_output
    @server.queue_response(200, { team: 'GXB', uid: 'u1', admin_email: 'christian@gxb.vc',
                                   credits_remaining: 0, total_credits: 0, credits_used: 0,
                                   current_plan: nil,
                                   subscription_mailbox_slots_google_remaining: 0, subscription_mailbox_slots_google: 0,
                                   subscription_mailbox_slots_ms_outlook_remaining: 0, subscription_mailbox_slots_ms_outlook: 0,
                                   auto_topup_enabled: false }.to_json)

    out = capture_stdout { cmd_account([], @cfg) }
    assert_match(/Team:\s+GXB/, out)
    assert_match(/Admin:\s+christian@gxb\.vc/, out)
  end

  def test_account_json_output
    @server.queue_response(200, { team: 'GXB' }.to_json)
    out = capture_stdout { cmd_account(['--format', 'json'], @cfg) }
    assert_equal({ 'team' => 'GXB' }, JSON.parse(out))
  end

  def test_workspaces_list_table
    @server.queue_response(200, { workspaces: [{ uid: 'w1', name: 'GXB', domains: 2, workspace_type: 'user' }] }.to_json)
    out = capture_stdout { cmd_workspaces_list([], @cfg) }
    assert_match(/w1/, out)
    assert_match(/GXB/, out)
  end

  def test_workspaces_list_empty
    @server.queue_response(200, { workspaces: [] }.to_json)
    out = capture_stdout { cmd_workspaces_list([], @cfg) }
    assert_equal("(no workspaces)\n", out)
  end

  def test_domains_list_requires_workspace
    cfg_no_ws = { key: 'test-key', workspace: nil }
    err = assert_raises(SystemExit) do
      capture_stdout { cmd_domains_list([], cfg_no_ws) }
    end
    assert_equal 2, err.status
  end

  def test_domains_list_sends_workspace_header
    @server.queue_response(200, { domains: [], total: 0, pages: 0, current_page: 1 }.to_json)
    capture_stdout { cmd_domains_list([], @cfg) }
    req = @server.requests.last
    assert_equal 'ws-123', req[:headers]['X-Workspace-Id']
    assert_equal 'POST', req[:method]
    assert_equal({ 'page' => 1, 'limit' => 10 }, JSON.parse(req[:body]))
  end

  def test_mailboxes_list_workspace_override_flag
    @server.queue_response(200, { mailboxes: [], total: 0, pages: 0, current_page: 1 }.to_json)
    capture_stdout { cmd_mailboxes_list(['--workspace', 'other-ws'], @cfg) }
    req = @server.requests.last
    assert_equal 'other-ws', req[:headers]['X-Workspace-Id']
  end

  def test_api_json_401_exits_1
    @server.queue_response(401, { message: 'bad key' }.to_json)
    err = assert_raises(SystemExit) do
      capture_stdout { api_json(:get, '/v1/api/account', @cfg) }
    end
    assert_equal 1, err.status
  end

  def test_render_table_empty_returns_false
    refute render_table([], [{ key: :a, label: 'A' }])
  end

  def test_render_table_truncates_flex_column
    ENV['COLUMNS'] = '30'
    rows = [{ short: 'x', long: 'a' * 100 }]
    cols = [{ key: :short, label: 'SHORT' }, { key: :long, label: 'LONG' }]
    out = capture_stdout { render_table(rows, cols, flex_key: :long) }
    assert_includes out, '…'
  ensure
    ENV.delete('COLUMNS')
  end

  def test_load_dotenv_parses_simple_kv
    require 'tempfile'
    Tempfile.create('env') do |f|
      f.write("INBOXKIT_API_KEY=abc123\n# comment\nINBOXKIT_WORKSPACE_UID=ws-1\n")
      f.flush
      parsed = load_dotenv(f.path)
      assert_equal 'abc123', parsed['INBOXKIT_API_KEY']
      assert_equal 'ws-1', parsed['INBOXKIT_WORKSPACE_UID']
    end
  end

  def test_raw_command_dispatches_method_and_path
    @server.queue_response(200, { ok: true }.to_json)
    out = capture_stdout { cmd_raw(['get', '/v1/api/account'], @cfg) }
    assert_equal({ 'ok' => true }, JSON.parse(out))
    req = @server.requests.last
    assert_equal 'GET', req[:method]
    assert_equal '/v1/api/account', req[:path]
  end

  def test_raw_command_rejects_invalid_json_data
    err = assert_raises(SystemExit) do
      capture_stdout { cmd_raw(['post', '/v1/api/x', '--data', 'not json'], @cfg) }
    end
    assert_equal 2, err.status
  end
end
