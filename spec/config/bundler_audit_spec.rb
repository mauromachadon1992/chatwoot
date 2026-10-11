require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
describe 'Ignored bundler-audit advisories' do
  # rubocop:enable RSpec/DescribeClass
  let(:framing_advisory) { 'GHSA-42qh-8mx8-7wqm' }
  let(:ignored) { YAML.load_file(Rails.root.join('.bundler-audit.yml')).fetch('ignore', []) }
  let(:rack_proxy) { Bundler::LockfileParser.new(Rails.root.join('Gemfile.lock').read).specs.find { |spec| spec.name == 'rack-proxy' } }

  # An ignore holds for every version of the gem, so the ignore has to be tied to the 0.x
  # it was written for: a rack-proxy in the 1.x the advisory is about would otherwise pass
  # the scan in silence.
  def tied_to_zero_x?(ignored, version)
    ignored.exclude?(framing_advisory) || version < Gem::Version.new('1.0.0')
  end

  # GHSA-42qh-8mx8-7wqm is framing in rack-proxy 1.0.0 to 1.0.2, and the advisory database
  # lists no unaffected range, so the scan flags the 0.x vite_ruby pins us to. Ignored
  # because the only proxy here is the Vite dev server's, in development, to our own Vite.
  it 'does not fail the security scan on the rack-proxy framing advisory' do
    expect(ignored).to include(framing_advisory)
  end

  it 'keeps that ignore tied to the 0.x rack-proxy it was written for' do
    message = "rack-proxy #{rack_proxy.version} is in the range #{framing_advisory} is about; drop the ignore"

    expect(tied_to_zero_x?(ignored, rack_proxy.version)).to be(true), message
  end

  # Bundler rewrites a lockfile edited to name a version that is not installed, so the
  # 1.x case is asserted on the check itself rather than on a doctored Gemfile.lock.
  it 'turns red once rack-proxy reaches the affected range' do
    expect(tied_to_zero_x?([framing_advisory], Gem::Version.new('1.0.2'))).to be(false)
    expect(tied_to_zero_x?([framing_advisory], Gem::Version.new('1.0.0'))).to be(false)
  end

  # The RubyLLM ReDoS advisories ignored in .bundler-audit.yml only exist on Ruby 3.1.x (no regex memoization before 3.2). An
  # ignore holds for every Ruby, so it is tied to the Ruby the app is pinned to: on 3.1 it would hide
  # a real exposure.
  describe 'the RubyLLM ReDoS advisories that only exist on Ruby 3.1.x' do
    let(:ruby_31_only) { %w[CVE-2026-67987 CVE-2026-67989 CVE-2026-67991] }

    it 'are ignored only while the app runs a Ruby that has regex memoization' do
      expect(ignored).to include(*ruby_31_only)
      expect(Gem::Version.new(RUBY_VERSION)).to be >= Gem::Version.new('3.2')
    end
  end
end
