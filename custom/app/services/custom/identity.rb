# The Flow identity (custom/contracts/identity.md) applied to this installation: the sign-in page row
# (Custom::LoginPage) that brands the auth screens, the tab title, the favicon and the logos for the whole
# installation. Idempotent, and only the identity is touched: a page an administrator already laid out
# keeps its layout, background and options. Nothing here is code to ship with the page: the SVGs are the
# contract's own files, the same bytes the agents repository applies to its interface.
module Custom::Identity
  NAME = 'flow-chat'.freeze
  ACCENT = '#3E63DD'.freeze
  DIR = Rails.root.join('custom/contracts/identity')
  FILES = { logo: 'flow-chat-light.svg', logo_dark: 'flow-chat-dark.svg', icon: 'flow-mark.svg' }.freeze
  COPY = {
    'pt_BR' => { 'title' => 'Entrar no flow-chat', 'subtitle' => 'Atendimento, negócios e agentes de IA no mesmo lugar.' },
    'en' => { 'title' => 'Sign in to flow-chat', 'subtitle' => 'Support, deals and AI agents in one place.' },
    'es' => { 'title' => 'Entrar en flow-chat', 'subtitle' => 'Atención, negocios y agentes de IA en un solo lugar.' }
  }.freeze

  module_function

  def apply!
    page = Custom::LoginPage.current
    page.assign_attributes(enabled: true, name: NAME, accent_color: ACCENT, copy: page.copy.to_h.deep_merge(COPY))
    FILES.each { |image, file| attach(page, image, file) }
    page.save!
    page
  end

  # Back to Chatwoot's own screens: the settings and the images go.
  def reset!
    Custom::LoginPage.reset!
  end

  # A file already attached with the same bytes stays as it is, so a second run changes nothing.
  def attach(page, image, file)
    path = DIR.join(file)
    attachment = page.public_send(image)
    return if current?(attachment, path)

    attachment.attach(io: path.open, filename: file, content_type: 'image/svg+xml')
  end

  # The same bytes AND the file still in storage: a database copied without its files must not look done.
  def current?(attachment, path)
    attachment.attached? && attachment.blob.checksum == Digest::MD5.base64digest(path.binread) &&
      attachment.blob.service.exist?(attachment.blob.key)
  end
end
