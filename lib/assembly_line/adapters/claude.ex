defmodule AssemblyLine.Adapters.Claude do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    IO.inspect "EVENT"
    IO.inspect event
    IO.inspect "CLAUDE LOGGING!"
    IO.inspect "CLAUDE API!"
    api_key = Application.get_env(:assembly_line, :claude_api_key, nil)

    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    client = Anthropix.init(api_key)

    {:ok, resp} =
      Anthropix.chat(client,
        # model: "claude-3-opus-20240229",
        model: event.step.module.model,
        messages: [wrap(event, "user", message)]
        # stream: true,
      ) |> IO.inspect


    {:ok, resp, event}
  end

  def deserialize(_event, %{"content" => completions}) do
    Enum.map(completions, fn completion -> get_in(completion, ["text"]) end)
    |> Enum.join("\n")
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
