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

    {:ok,
     [
       "https://zvukipro.com/uploads/posts/2020-06/1593335700_30094-bears-nature-animals-grizzly_bear-grizzly_bears.jpg"
     ], event}
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
