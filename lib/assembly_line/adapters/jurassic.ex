defmodule AssemblyLine.Adapters.Jurassic do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    ExAws.Bedrock.invoke_model(event.step.module.model, %{
      "countPenalty" => %{"scale" => 0},
      "frequencyPenalty" => %{"scale" => 0},
      "maxTokens" => 200,
      "presencePenalty" => %{"scale" => 0},
      "prompt" => message,
      "temperature" => 0,
      "topP" => 1
    })
    |> ExAws.request!(service_override: :bedrock, region: "us-west-2")
  end

  def deserialize(_event, %{"completions" => completions}) do
    Enum.map(completions, fn completion -> get_in(completion, ["data", "text"]) end)
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
