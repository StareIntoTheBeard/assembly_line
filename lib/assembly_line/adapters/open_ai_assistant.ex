defmodule AssemblyLine.Adapters.OpenAIAssistant do
  alias OpenaiEx.Beta.Threads
  alias OpenaiEx.ChatMessage
  use AssemblyLine.Adapter

  @enforce_keys [:assistant_id, :vector_store_id]
  defstruct [
    # :file_ids,
    :assistant_id,
    :vector_store_id
    # :conversation_id,
    # :run_id,
    # :thread_id
  ]

  # def run({event, messages}) do
  def run(event) do
    openai_client = AssemblyLine.Adapters.OpenAIAssistant.Client.new()
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    # Enum.map(event.context, fn message ->
      openai_client
      |> Threads.Messages.create(
        AssemblyLine.get_remote_thread(event),
        wrap(event, "user", message)
      )
    # end)

    # jbean todo get this out of routing
    run_req =
      Threads.Runs.new(
        thread_id: AssemblyLine.get_remote_thread(event),
        assistant_id: event.step.routing.assistant_id,
        response_format: event.step.module.response_format
      )
      IO.inspect "run>"
      res =
      openai_client
      |> Threads.Runs.create(run_req)
      |> IO.inspect

    {:ok, res, event}
  end

  def wrap(%AssemblyLine.Event{assigns: %{file_id: file_id}}, "user", message),
    # do: ChatMessage.user(message, [file_id])
    do:
      Threads.Messages.new(
        role: "user",
        content: message,
        attachments: [%{file_id: file_id, tools: [%{type: "file_search"}]}]
      )

  def wrap(%AssemblyLine.Event{}, "user", message),
    # do: ChatMessage.user(message, [])
    do: ChatMessage.user(message)

  def wrap(%AssemblyLine.Event{}, "system", message),
    do: ChatMessage.system(message)

  def wrap(%AssemblyLine.Event{}, "assistant", message),
    do: ChatMessage.assistant(message)

  def deserialize(event, _response) do
    AssemblyLine.Adapters.OpenAIAssistant.Poller.run(event)
    |> Map.get("content")
    |> Enum.reduce([], fn content, acc ->
      acc ++ [Map.get(content, "text") |> Map.get("value")]
    end)
  end

  def generate_thread() do
    thread =
      AssemblyLine.Adapters.OpenAIAssistant.Client.new()
      |> OpenaiEx.Beta.Threads.create()

    thread["id"]
  end
end
