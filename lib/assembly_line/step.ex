defmodule AssemblyLine.Step do
  use Accessible

  defstruct [
    :module,
    :adapter,
    :routing,
    :prompt,
    :opts,
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
  @callback opts() :: map()

  # todo do this right
  def exception(args), do: args

  defmacro __using__(_opts) do
    quote do
      use Assignable
      import Assignable.Helpers

      @behaviour AssemblyLine.Step

      def init,
        do:
          struct(AssemblyLine.Step, %{
            adapter: adapter(),
            module: __MODULE__,
            routing: adapter().init(route()),
            opts: opts()
          })

      def prompt(%{step: %{prompt: prompt}}) do
        prompt
      end

      def prompt(%{step: %{module: step_module}} = event) do
        event.assigns
        |> step_module.prompt()
      end

      def compile_prompt(event) do
        verbose = Map.has_key?(event.step.opts(), :verbose)
        compiler = Map.has_key?(event.step.routing, :compiler)

        assigns =
          event.assigns
          |> event.step.module.validate_assigns(verbose: verbose, compiler: compiler)

        prompt =
          assigns
          |> prompt()
          |> String.trim()

        {prompt, assigns}
      end

      def compile_arbitrary_prompt(event) do
        verbose = Map.has_key?(event.step.opts(), :verbose)
        compiler = Map.has_key?(event.step.routing, :compiler)

        assigns =
          event.assigns
          |> event.step.module.validate_assigns(verbose: verbose, compiler: compiler)

        prompt = event.step.prompt

        {prompt, assigns}
      end

      def dial_agent, do: {}
      def response_format, do: "text"
      def adapter, do: AssemblyLine.PhoneBook.fetch_agent(__MODULE__.dial_agent()).adapter
      def route, do: AssemblyLine.PhoneBook.fetch_agent(__MODULE__.dial_agent()).route

      def opts do
        agent = AssemblyLine.PhoneBook.fetch_agent(__MODULE__.dial_agent())
        opts_present? = Map.has_key?(agent, :opts)

        case opts_present? do
          true ->
            Map.merge(agent.opts, __MODULE__.adapter().opts())

          false ->
            __MODULE__.adapter().opts()
        end
      end

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
                     opts: 0,
                     break_word: 0,
                     dial_agent: 0,
                     after_step: 1,
                     before_step: 1
    end
  end

  def step_guard(event, _) when is_map_key(event.step.opts, :disable_step_hooks) do
    event
  end

  def step_guard(event, step_key) do
    apply(event.step.module, step_key, [event])
  end

  def set_is_arbitrary?(%AssemblyLine.Step{} = step, true) do
    put_in(step, [:_private, :is_arbitrary?], true)
  end

  def get_is_arbitrary?(%AssemblyLine.Step{} = step) do
    get_in(step, [:_private, :is_arbitrary?])
  end
end
