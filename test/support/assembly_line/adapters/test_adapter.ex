defmodule AssemblyLine.Adapters.TestAdapter do
  use AssemblyLine.Adapter

  defstruct [
    :disable_conversation_recording
  ]

  # implement call to model
  def run(_event) do
    %{"citations" => ["response from the run", "some other response"]}
  end

  # parse response from llm
  def deserialize(_event, %{"citations" => citations}) do
    citations
    |> Enum.join("\n ")
  end

  # prepare individual message for sent to llm
  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
