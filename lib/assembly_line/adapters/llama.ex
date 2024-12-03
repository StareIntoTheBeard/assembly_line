defmodule AssemblyLine.Adapters.LLaMa do
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
      "max_gen_len" => 2048,
      "prompt" => message,
      "temperature" => 0.1,
      "top_p" => 1
    })
    |> ExAws.request!(service_override: :bedrock, region: "us-west-2")
    |> IO.inspect()
  end

  def deserialize(_event, %{"generation" => completions}) do
    completions
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
