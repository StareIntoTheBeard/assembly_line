defmodule AssemblyLine.Adapters.Debug do
  use AssemblyLine.Adapter
  @enforce_keys [:verbose]
  defstruct [
    :verbose
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    dbg("running debugger")
    dbg("event")
    dbg(event)
    dbg("message")
    dbg(message)

    {:ok, "debug response", event}
  end

  def deserialize(event, responses) do
    dbg("Deserializing...")
    dbg("deserializing - event")
    dbg(event)
    dbg("deserializing - responses")
    dbg(responses)
    responses
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
