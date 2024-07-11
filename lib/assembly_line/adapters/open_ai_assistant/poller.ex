defmodule AssemblyLine.Adapters.OpenAIAssistant.Poller do
  def run(event) do
    openai_client = AssemblyLine.Adapters.OpenAIAssistant.Client.new()
    IO.inspect("sleeping")
    Process.sleep(5000)
    thread_id = AssemblyLine.get_remote_thread(event)

    response =
      openai_client |> OpenaiEx.Beta.Threads.Messages.list(thread_id)

    Map.get(response, "data")

    Enum.find(Map.get(response, "data"), fn data ->
      data["role"] == "assistant" && data["content"] != []
    end)
    |> poll(event)
  end

  defp poll(nil, event) do
    run(event)
  end

  defp poll([], event) do
    run(event)
  end

  defp poll(response, _event) do
    response
  end
end
