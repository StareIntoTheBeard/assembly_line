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
      use AssemblyLine.Assigner

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
        event.assigns
        |> step_module.prompt()
      end

      def compile_prompt(event) do
        debug = Map.has_key?(event.step.routing, :debug)

        assigns = event.assigns
        |> event.step.module.validate_assigns(debug)

        prompt = assigns
        |> prompt()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()
        |> String.trim()
        {prompt, assigns}
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

      def run_before_step(event) do
        AssemblyLine.Step.step_guard(event, :before_step)
      end

      def run_after_step(event) do
        AssemblyLine.Step.step_guard(event, :after_step)
      end

      defoverridable response_format: 0,
                     model: 0,
                     prompt: 1,
                     break_word: 0,
                     dial_agent: 0,
                     after_step: 1,
                     before_step: 1
    end
  end

  def step_guard(event, _) when is_map_key(event.step.routing, :debug) do
    event
  end

  def step_guard(event, step_key) do
    apply(event.step.module, step_key, [event])
    |> step_return(event)
  end

  defp step_return(%AssemblyLine.Event{} = reply, _), do: reply
  defp step_return(_, %AssemblyLine.Event{} = event), do: event

  def set_is_arbitrary?(%AssemblyLine.Step{} = step, true) do
    put_in(step, [:_private, :is_arbitrary?], true)
  end

  def get_is_arbitrary?(%AssemblyLine.Step{} = step) do
    get_in(step, [:_private, :is_arbitrary?])
  end
end
