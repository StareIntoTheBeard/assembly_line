defmodule AssemblyLine.Adapters.Groq do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    response = Groq.ChatCompletion.create(%{
      "model" => event.step.module.model(),
      "messages" => [wrap(event, "user", message)]
    })

    {:ok, response, event}
  end

  def deserialize(_event, {:ok, %{"choices" => responses}}) do
    Enum.map(responses, fn response -> get_in(response, ["message", "content"]) end)
    |> Enum.join("\n ")
  end

  def deserialize(_event, thing) do
    inspect thing
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
