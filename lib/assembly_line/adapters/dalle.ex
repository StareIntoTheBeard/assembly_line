defmodule AssemblyLine.Adapters.DallE do
  use AssemblyLine.Adapter
  @enforce_keys [:model, :size]
  defstruct [
    :model,
    :size
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    img_req =
      OpenaiEx.Images.Generate.new(
        prompt: message,
        model: event.step.module.model,
        size: event.step.routing.size,
        n: event.assigns.amount
      )

    {:ok, response} =
      AssemblyLine.Adapters.OpenAIAssistant.Client.new()
      |> OpenaiEx.with_receive_timeout(99999)
      |> OpenaiEx.Images.generate(img_req)

    {:ok, response, event}
  end

  def deserialize(_event, %{"data" => responses}) do
    Enum.map(responses, fn response -> get_in(response, ["url"]) end)
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
