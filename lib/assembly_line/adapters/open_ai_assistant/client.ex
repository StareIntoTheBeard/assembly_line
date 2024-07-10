defmodule AssemblyLine.Adapters.OpenAIAssistant.Client do
  def new() do
    Application.get_env(:openai, :api_key)
    |> OpenaiEx.new()
  end
end
