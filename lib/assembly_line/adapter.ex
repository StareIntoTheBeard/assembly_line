defmodule AssemblyLine.Adapter do
  @callback init(map()) :: struct()
  @callback run(struct()) :: term()
  @callback opts() :: map
  @callback deserialize(struct(), term()) :: list(map())
  @callback wrap(struct(), String.t(), String.t()) :: map()
  defmacro __using__(_opts) do
    quote do
      @behaviour AssemblyLine.Adapter
      def init(params \\ %{}), do: struct(__MODULE__, params)

      def generate_thread(), do: nil
      def opts(), do: %{}

      defoverridable generate_thread: 0, opts: 0
    end
  end
end
