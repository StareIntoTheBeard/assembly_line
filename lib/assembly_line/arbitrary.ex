defmodule AssemblyLine.ArbitraryPipeline do
  defmacro __using__(_opts) do
    quote do
      use AssemblyLine.Manager

    end
  end
end

defmodule AssemblyLine.ArbitraryStep do
  defmacro __using__(_opts) do
    quote do
      use AssemblyLine.Step
      def init(_event, nil), do: raise("Arbitrary steps require a prompt at definition.")

      def init(_event, prompt), do: %{init() | prompt: prompt, _private: %{is_arbitrary?: true}}
      def prompt(event), do: super(event)

      def dial_agent(), do: {:foundation, :gpt4}

      defoverridable init: 2, dial_agent: 0
    end
  end
end

