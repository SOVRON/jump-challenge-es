defmodule Jump.Messaging.Conversation do
  @moduledoc """
  Lightweight conversation summary used to power the chat sidebar.
  """

  @enforce_keys [:id, :scope, :source_id, :last_message_at]
  defstruct [
    :id,
    :scope,
    :source_id,
    :thread_id,
    :task_id,
    :title,
    :preview,
    :last_message_at,
    :last_role,
    :messages_count,
    :participants
  ]
end
