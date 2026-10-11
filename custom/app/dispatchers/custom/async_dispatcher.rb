# Picked up by `AsyncDispatcher.prepend_mod_with('AsyncDispatcher')` because `custom` is one
# of ChatwootApp.extensions.
module Custom::AsyncDispatcher
  def listeners
    super + [Custom::Kanban::ConversationListener.instance]
  end
end
