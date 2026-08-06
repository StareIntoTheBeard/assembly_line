defmodule Memories.UserActionHelpers do
  def chat_to_agent(message, assigns) do
    full_conversation_context = assigns.full_conversation_context
    current_internal_thread_id = assigns.current_internal_thread_id

    updated_conversation =
      Enum.concat(assigns.conversation, [
        %{message: message, from: :user, sender_user_id: assigns.current_user.id}
      ])

    Memories.update_memory(
      message,
      :user,
      assigns.current_user.id,
      current_internal_thread_id
    )

    event =
      assigns.assistant_event
      |> AssemblyLine.update_assigns(%{
        previous_messages: full_conversation_context,
        latest_message: message
      })

    %{event: event, updated_conversation: updated_conversation}
  end
end
