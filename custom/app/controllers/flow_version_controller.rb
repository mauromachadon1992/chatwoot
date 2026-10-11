# What this installation is running, public like /api: the fork's own release (the git tag `flow-chat-vX.Y.Z`, baked
# into the image as FLOW_VERSION), the Chatwoot version it is built on and the commit. A person or a monitor can tell
# which build answers without opening the dashboard.
class FlowVersionController < ActionController::Base # rubocop:disable Rails/ApplicationController
  REVISION_FILE = Rails.root.join('.git_sha').freeze

  def show
    expires_in 1.minute, public: true
    render json: { product: 'flow-chat', version: ENV['FLOW_VERSION'].presence, chatwoot_version: Chatwoot.config[:version],
                   revision: revision }
  end

  private

  def revision
    REVISION_FILE.exist? ? REVISION_FILE.read.strip.first(9).presence : nil
  end
end
