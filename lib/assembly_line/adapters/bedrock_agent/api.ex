defmodule AssemblyLine.Adapters.BedrockAgent.Api do
  def request(data \\ %{}, %{
        agent_id: agent_id,
        agent_alias: agent_alias,
        conversation_id: conversation_id
      }) do
    config = Application.get_all_env(:ex_aws)

    url =
      "https://bedrock-agent-runtime.#{config[:default_region]}.amazonaws.com/agents/#{agent_id}/agentAliases/#{agent_alias}/sessions/#{conversation_id}/text"

    {:ok, headers, body} = headers(data, :post, config, :"bedrock-agent-runtime", url)

    {:ok, resp} = HTTPoison.post(url, body, headers, timeout: :infinity, recv_timeout: :infinity)
    AssemblyLine.Adapters.BedrockAgent.StreamProcessor.decode(resp)
  end

  def train(data \\ %{}, %{
        knowledge_base_id: knowledge_base_id,
        data_source_id: data_source_id
      }) do
    config = Application.get_all_env(:ex_aws)

    url =
      "https://bedrock-agent.#{config[:default_region]}.amazonaws.com/knowledgebases/#{knowledge_base_id}/datasources/#{data_source_id}/ingestionjobs/"

    {:ok, headers, body} = headers(data, :put, config, :"bedrock-agent", url)

    {:ok, _resp} = HTTPoison.put(url, body, headers, timeout: :infinity, recv_timeout: :infinity)
  end

  defp headers(data, method, config, service, url) do
    user_agent = "hackney/1.20.1 ex_aws/bedrock/2.5.1"

    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", user_agent},
      {"x-amzn-bedrock-accept", "*/*"}
    ]

    body = Jason.encode!(data)

    {:ok, headers} =
      ExAws.Auth.headers(
        method,
        url,
        service,
        %{
          port: 443,
          scheme: "https://",
          host: "#{service}.#{config[:default_region]}.amazonaws.com",
          access_key_id: config[:access_key_id],
          secret_access_key: config[:secret_access_key],
          service_override: :bedrock,
          region: config[:default_region],
          retries: [max_attempts: 10, base_backoff_in_ms: 10, max_backoff_in_ms: 10000],
          json_codec: Jason,
          http_client: ExAws.Request.Hackney,
          normalize_path: true,
          require_imds_v2: false
        },
        headers,
        body
      )

    {:ok, headers, body}
  end
end
