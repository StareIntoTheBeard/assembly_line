defmodule AssemblyLine.Adapters.DallE do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    img_req = OpenaiEx.Images.Generate.new(prompt: message, size: "1792x1024", n: event.assigns.amount)

    {:ok, response} =  AssemblyLine.Adapters.OpenAIAssistant.Client.new()
    |> OpenaiEx.Images.generate(img_req)

    {:ok, response, event}
  end

  def deserialize(_event, %{"data" => responses}) do
    Enum.map(responses, fn response -> get_in(response, ["url"]) end)
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end


alias OpenaiEx.Images
