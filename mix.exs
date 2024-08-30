defmodule AssemblyLine.MixProject do
  use Mix.Project

  def project do
    [
      app: :assembly_line,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:openai, "~> 0.5.4"},
      {:openai_ex, git: "https://github.com/Subatomic-Agency/openai_ex.git"},
      {:ex_aws, git: "https://github.com/Subatomic-Agency/ex_aws.git", override: true},
      {:ex_aws_bedrock, "~> 2.5.1"},
      {:ex_aws_s3, "~> 2.5"},
      {:gen_stage, "~> 1.2"},
      {:accessible, "~> 0.3.0"},
      {:anthropix, "~> 0.3"},
      {:uuid, "~> 1.1"},
      {:nosql, path: "../nosql_utils"}
    ]
  end
end
