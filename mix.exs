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
      extra_applications: [:logger],
      mod: {AssemblyLine.Application, []},
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:openai, "~> 0.6.2"},
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
       ref: "11ddec3f5dce0ea7ef26558bce7b9893863e591b"},
      {:nosql,
       git: "git@github.com:microdose-ai-team/nosql_utils.git",
       ref: "2e052fc08748113d14058817c45e1e3edcfe478a"},
      {:groq, "~> 0.1.0",
       [
         git: "https://github.com/microdose-ai-team/groq-elixir.git",
         ref: "601ca1868967c3d7699083b14fc7ed47961c7926"
       ]},
      # {:nosql, path: "../nosql_utils"}
    ]
  end
end
