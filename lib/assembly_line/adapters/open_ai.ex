defmodule AssemblyLine.Adapters.OpenAI do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    {:ok, resp} =
      OpenAI.chat_completion(
        model: event.step.module.model,
        response_format: %{type: event.step.module.response_format},
        messages: [wrap(event, "user", message)],
        temperature: 0.2,
        max_tokens: 4096
      )
      |> IO.inspect()

    {:ok, resp, event}
  end

  def deserialize(_event, %{choices: responses}) do
    Enum.map(responses, fn response -> get_in(response, ["message", "content"]) end)
    |> Enum.join("\n ")
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
