defmodule AssemblyLine.Step do
  use Accessible

  defstruct [
    :module,
    :adapter,
    :routing,
    :prompt,
    _private: %{is_arbitrary?: false}
  ]

  @callback init() :: struct()
  @callback response_format() :: term()
  @callback prompt(struct()) :: binary()
  @callback before_step(struct()) :: struct()
  @callback after_step(struct()) :: struct()
  @callback on_failure(struct()) :: struct()
  @callback adapter() :: module()
  @callback route() :: map()

  # todo do this right
  def exception(args), do: args

  defmacro __using__(_opts) do
    quote do
      @behaviour AssemblyLine.Step
      def init,
        do:
          struct(AssemblyLine.Step, %{
            adapter: adapter(),
            module: __MODULE__,
            routing: adapter().init(route())
          })

      def prompt(%{step: %{prompt: prompt}}) do
        prompt
      end

      def prompt(%{step: %{module: step_module}} = event) do
        step_module.prompt(event)
      end

      def dial_agent, do: {}
      def response_format, do: "text"
      def adapter, do: AssemblyLine.PhoneBook.fetch_agent(__MODULE__.dial_agent()).adapter
      def route, do: AssemblyLine.PhoneBook.fetch_agent(__MODULE__.dial_agent()).route

      def model do
        route =
          __MODULE__.dial_agent()
          |> AssemblyLine.PhoneBook.fetch_agent()
          |> Map.get(:route)

        if Map.has_key?(__MODULE__.route(), :model) do
          route.model
        else
          raise AssemblyLine.Step, "model/0 called on Assistant step"
        end
      end

      def break_word, do: "AI HALT REQUESTED"
      def before_step(%AssemblyLine.Event{} = event), do: Function.identity(event)
      def after_step(%AssemblyLine.Event{} = event), do: Function.identity(event)
      def on_failure(%AssemblyLine.Event{} = event), do: Function.identity(event)

      defoverridable response_format: 0,
                     model: 0,
                     prompt: 1,
                     break_word: 0,
                     dial_agent: 0,
                     after_step: 1,
                     before_step: 1
    end
  end

  def set_is_arbitrary?(%AssemblyLine.Step{} = step, true) do
    put_in(step, [:_private, :is_arbitrary?], true)
  end

  def get_is_arbitrary?(%AssemblyLine.Step{} = step) do
    get_in(step, [:_private, :is_arbitrary?])
  end
end
