defmodule AssemblyLine.Adapters.Compiler do
  use AssemblyLine.Adapter
  # @enforce_keys [:disable_step_hooks, :disable_conversation_recording, :verbose]
  defstruct [:disable_step_hooks,
            :disable_conversation_recording, :compiler]

  def run(event) do
    {:ok,
     [
       "https://zvukipro.com/uploads/posts/2020-06/1593335700_30094-bears-nature-animals-grizzly_bear-grizzly_bears.jpg"
     ], event}
  end

  def deserialize(_event, responses) do
    responses
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
