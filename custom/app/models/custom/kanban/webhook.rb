# An address an administrator wants told about deals. Account-level, not per board: it hears
# about every board of the account, which is why only administrators manage it. The secret signs
# each delivery (WebhookSender) and is shown once, when the webhook is created.
class Custom::Kanban::Webhook < ApplicationRecord
  EVENTS = %w[deal.created deal.moved deal.won deal.lost deal.value_changed task.created].freeze
  MAX_PER_ACCOUNT = 10
  URL_MAX_LENGTH = 2048

  belongs_to :account
  has_many :deliveries, class_name: 'Custom::Kanban::WebhookDelivery', dependent: :delete_all

  before_validation :normalize
  before_create { self.secret = SecureRandom.hex(24) }

  validates :url, presence: true, length: { maximum: URL_MAX_LENGTH }
  validate :url_is_https
  validate :events_are_known
  validate :room_in_account, on: :create

  scope :ordered, -> { order(:id) }
  scope :listening_to, ->(event) { where(active: true).where('? = ANY (events)', event) }

  # Never the secret: it leaves the server once, in the create response.
  def push_event_data
    { id: id, url: url, events: events, active: active, created_at: created_at.to_i }
  end

  private

  def normalize
    self.url = url.to_s.strip
    self.events = Array(events).compact_blank.uniq & EVENTS
  end

  def url_is_https
    uri = URI.parse(url.to_s)
    errors.add(:url, :https) unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:url, :https)
  end

  def events_are_known
    errors.add(:events, :empty) if events.empty?
  end

  def room_in_account
    errors.add(:base, :too_many, max: MAX_PER_ACCOUNT) if self.class.where(account_id: account_id).count >= MAX_PER_ACCOUNT
  end
end
