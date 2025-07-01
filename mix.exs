defmodule AssemblyLine.MixProject do
  use Mix.Project

  def project do
    [
      app: :assembly_line,
      version: "1.0.0",
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
      {:openai_ex, git: "https://github.com/microdose-ai-team/openai_ex.git"},
      {:ex_aws, git: "https://github.com/microdose-ai-team/ex_aws.git", override: true},
      {:ex_aws_bedrock, "~> 2.5.1"},
      {:ex_aws_s3, "~> 2.5"},
      {:gen_stage, "~> 1.2"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:accessible, "~> 0.3.0"},
      {:anthropix, "~> 0.3"},
      {:dialyxir, "~> 1.4", runtime: false},
      {:uuid, "~> 1.1"},
      {:horde, "~> 0.9.0"},
      # {:assignable, path: "../assignable"},
      {:assignable,
       git: "git@github.com:microdose-ai-team/assignable.git",
       ref: "827ef5319335d519e2ccfd10c84f2ec14f73674d"},
      {:nosql,
       git: "git@github.com:microdose-ai-team/nosql_utils.git",
       ref: "81c630362b2e3295141ad72682de285357796398"}
      # {:nosql, path: "../nosql_utils"}
    ]
  end
end
