# The bell of the Kanban: the current agent's own notifications, on the boards they still see.
class Api::V1::Accounts::Kanban::NotificationsController < Api::V1::Accounts::Kanban::BaseController
  PER_PAGE = 30

  def index
    page = [params[:page].to_i, 1].max
    notifications = listed.newest_first.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    render json: { payload: notifications.map(&:push_event_data), meta: meta }
  end

  def update
    notification = listed.find(params[:id])
    notification.update!(read_at: Time.current) unless notification.read?
    render json: { payload: notification.push_event_data, meta: meta }
  end

  def read_all
    # Timestamps only: nothing to validate, and a row per callback would be a row per notification.
    listed.unread.update_all(read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    render json: { meta: meta }
  end

  private

  def listed
    Custom::Kanban::Notification.listed_for(Current.user, Current.account)
  end

  def meta
    { unread_count: listed.unread.count, total_count: listed.count }
  end
end
