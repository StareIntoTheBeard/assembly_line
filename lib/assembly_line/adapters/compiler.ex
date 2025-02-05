defmodule AssemblyLine.Adapters.Compiler do
  use AssemblyLine.Adapter

  defstruct [compiler: true]

  def opts(),
    do: %{disable_step_hooks: true, disable_conversation_recording: true}

  def run(event) do
    {:ok, "compiled with assigns #{inspect(event.assigns)}", event}
  end

  def deserialize(_event, responses) do
    responses
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
