import Config

if Mix.env() == :test do
  config :assembly_line, AssemblyLine.PhoneBook, %{
    test: %{
      basic: %{
        adapter: AssemblyLine.Adapters.TestAdapter,
        route: %{
          disable_conversation_recording: true
        }
      }
    }
  }
end
dbg Application.get_all_env(:assembly_line)
# make this better config dummy
config :openai,
  # find it at https://platform.openai.com/account/api-keys
  api_key: Application.get_env(:assembly_line, :openai_api_key, nil),
  # find it at https://platform.openai.com/account/org-settings under "Organization ID"
  organization_key: Application.get_env(:assembly_line, :openai_organization_key, nil),
  # optional, passed to [HTTPoison.Request](https://hexdocs.pm/httpoison/HTTPoison.Request.html) options
  http_options: [recv_timeout: :infinity],
  # optional, useful if you want to do local integration tests using Bypass or similar
  # (https://github.com/PSPDFKit-labs/bypass), do not use it for production code,
  # but only in your test config!
  # api_url: "http://localhost/"
  api_url: "https://api.openai.com/"

# config :groq, api_key: S, hackney_pool_timeout: 20_000
config :groq,
  api_key: Application.get_env(:assembly_line, :groq_api_key, nil),
  hackney_pool_timeout: 20_000
