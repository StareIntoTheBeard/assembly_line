defmodule AssemblyLine.Adapters.Local do
  use AssemblyLine.Adapter
  @enforce_keys []
  defstruct [
  ]

  # implement call to model
  def run(event) do
    input =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    AssemblyLine.Adapters.Local.Api.request(%{message: input})
  end

  # parse response from llm
  def deserialize(_event, %{"choices" => choices}) do
    choices
    |> Enum.map(fn choice ->
      get_in(choice, ["message", "content"])
    end)
    |> Enum.join("\n ")
  end

  # prepare individual message for sent to llm
  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
