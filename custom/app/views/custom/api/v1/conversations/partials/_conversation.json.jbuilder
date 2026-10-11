# The deal a conversation belongs to, in the Pro dialect (operation 15 of custom/contracts/pro-kanban.md):
# one card or null. Only on reading a single conversation: a list would ask the database for each row.
# The answer goes to people signed in with a user token and is narrowed to the boards that user sees.
# It is never added to what reaches a contact (the widget): Conversations::EventDataPresenter builds
# that from an allowlist, and this partial is not part of it.
if controller.controller_name == 'conversations' && controller.action_name == 'show'
  json.kanban_task Custom::Kanban::ProSerializer.card_for_conversation(conversation, Current.user)
end
