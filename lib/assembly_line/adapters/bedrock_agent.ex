defmodule AssemblyLine.Adapters.BedrockAgent do
  use AssemblyLine.Adapter
  @complexity 5
  @enforce_keys [:agent_id, :agent_alias]
  defstruct [
    :agent_id,
    :agent_alias
  ]

  # implement call to model
  def run(event) do
    input =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    AssemblyLine.Adapters.BedrockAgent.Api.request(%{inputText: input}, %{
      agent_id: event.step.module.route.agent_id,
      agent_alias: event.step.module.route.agent_alias,
      conversation_id: AssemblyLine.get_remote_thread(event)
    })
  end

  # parse response from llm
  def deserialize(_event, %{"citations" => citations}) do
    citations
    |> Enum.map(fn citation ->
      get_in(citation, ["generatedResponsePart", "textResponsePart", "text"])
    end)
    |> Enum.join("\n ")
  end

  # parse response from llm
  def deserialize(_event, resp) when is_binary(resp) do
    Base.decode64!(resp)
  end

  # prepare individual message for sent to llm
  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}

  def generate_thread() do
    :crypto.strong_rand_bytes(@complexity)
    |> Base.url_encode64(padding: false)
    |> String.upcase()
  end
end
