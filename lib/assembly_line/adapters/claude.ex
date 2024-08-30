defmodule AssemblyLine.Adapters.Claude do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    {:ok, stream} = Anthropix.chat(client, [
      model: "claude-3-opus-20240229",
      messages: messages,
      stream: true,
    ])

    stream
    |> Stream.each(&update_ui_with_chunk/1)
    |> Stream.run()
  end

  def deserialize(_event, %{"completions" => completions}) do
    Enum.map(completions, fn completion -> get_in(completion, ["data", "text"]) end)
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
