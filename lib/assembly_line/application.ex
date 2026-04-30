defmodule AssemblyLine.Application do
  use Application

  def start(_type, _args) do
    Application.put_env(:openai, :api_key, Application.get_env(:assembly_line, :openai_api_key))

    Application.put_env(
      :openai,
      :organization_key,
      Application.get_env(:assembly_line, :openai_organization_key)
    )

    Application.put_env(:groq, :api_key, Application.get_env(:assembly_line, :groq_api_key))
    Supervisor.start_link([], strategy: :one_for_one)
  end
end
