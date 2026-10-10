require 'net/http'
require 'resolv'
require 'ipaddr'

# One POST of a delivery. The body is signed with the webhook's secret over "<timestamp>.<body>"
# (header X-Flow-Signature: t=<timestamp>,v1=<hex>), so a receiver can check who sent it and that
# it is fresh. The address must be https and must not resolve to this machine or a private
# network; the connection goes to the address that was checked (no DNS rebinding) and redirects
# are not followed.
class Custom::Kanban::WebhookSender
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  ERROR_MAX_LENGTH = 200

  Result = Struct.new(:http_status, :error, :duration_ms, :retryable, keyword_init: true) do
    def success?
      error.nil? && http_status.to_i.between?(200, 299)
    end
  end

  class BlockedAddress < StandardError; end

  # Everything that is not the public internet: this host, private and shared networks, link-local
  # (cloud metadata), multicast, reserved and documentation ranges, and the IPv6 forms that carry an
  # IPv4 address inside (NAT64).
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
    192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/96 ::1/128 64:ff9b::/96 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  def self.signature(secret, timestamp, body)
    "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
  end

  def initialize(webhook, delivery)
    @webhook = webhook
    @delivery = delivery
  end

  def call
    uri = URI.parse(@webhook.url)
    address = checked_address(uri.host)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = post(uri, address)
    result(response.code.to_i, nil, started, retryable: retryable_status?(response.code.to_i))
  rescue BlockedAddress => e
    Result.new(error: e.message, retryable: false, duration_ms: 0)
  rescue StandardError => e
    result(nil, "#{e.class.name.demodulize}: #{e.message}".truncate(ERROR_MAX_LENGTH), started || Process.clock_gettime(Process::CLOCK_MONOTONIC),
           retryable: true)
  end

  private

  def post(uri, address)
    body = @delivery.payload.to_json
    timestamp = Time.current.to_i
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.ipaddr = address
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Post.new(uri.request_uri, headers(timestamp, body))
    request.body = body
    http.request(request)
  end

  def headers(timestamp, body)
    { 'Content-Type' => 'application/json', 'User-Agent' => 'FlowAgents-Webhook/1',
      'X-Flow-Event' => @delivery.event, 'X-Flow-Delivery' => @delivery.id.to_s,
      'X-Flow-Signature' => self.class.signature(@webhook.secret, timestamp, body) }
  end

  def checked_address(host)
    addresses = Resolv.getaddresses(host)
    raise BlockedAddress, 'unresolved_host' if addresses.empty?
    raise BlockedAddress, 'blocked_address' if addresses.any? { |ip| internal?(ip) }

    addresses.first
  end

  def internal?(ip)
    address = IPAddr.new(ip)
    address = address.native if address.ipv6? && address.ipv4_mapped?
    BLOCKED_RANGES.any? { |range| range.include?(address) }
  rescue IPAddr::InvalidAddressError
    true
  end

  # A client error is the receiver saying no; trying again would only repeat it. A timeout, a
  # busy or a broken receiver may recover.
  def retryable_status?(code)
    code >= 500 || [408, 429].include?(code)
  end

  def result(http_status, error, started, retryable:)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    error ||= "HTTP #{http_status}" unless http_status.to_i.between?(200, 299)
    Result.new(http_status: http_status, error: error, duration_ms: ms, retryable: retryable)
  end
end
