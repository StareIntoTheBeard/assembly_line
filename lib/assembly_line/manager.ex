defmodule AssemblyLine.Manager do
  # can i test that every part fires at each event at least maybe with an adapter?
  # Should this all just be in a try do so it has another method of not continuing should something fail?
  # ...I think this won't be a problem w/ the evented system....
  defmacro __using__(_opts) do
    quote do
      def compile(%AssemblyLine.Event{} = event) do
        event = %{event | assembly_line: __MODULE__}
        step_list = AssemblyLine.get_step_list(event)

        event = %{event | step_list: step_list}

        AssemblyLine.Manager.event_check(event)

        event = __MODULE__.init(event)

        event =
          Enum.reduce_while(step_list, event, fn step, acc ->
            AssemblyLine.Manager.run_compiler(step, acc)
          end)
        verbose = Map.has_key?(event.step.routing, :verbose)
        if verbose, do: dbg event
        event
      end

      def execute(%AssemblyLine.Event{} = event) do
        %{assigns: assigns} = compile(event)
        event = %{event | assigns: assigns, assembly_line: __MODULE__}
        step_list = AssemblyLine.get_step_list(event)

        event = %{event | step_list: step_list}

        AssemblyLine.Manager.event_check(event)

        event = __MODULE__.init(event)

        event =
          Enum.reduce_while(step_list, event, fn step, acc ->
            AssemblyLine.Manager.run(step, acc)
          end)

        if is_map(event),
          do: __MODULE__.on_completion(event)
      end

      def steps(), do: []
      def init(event), do: Function.identity(event)
      def on_completion(event), do: Function.identity(event)
      #####
      # Possible State Machine Hooks
      # To give people the option to modify the event during the step runs
      #####
      # Post Seed Hook
      # Pre AI Hook
      # Post AI Hook
      # Circuit Break Hook
      #####
      # def handle_event(%AssemblyLine.Event{state: :init} = event), do: %{event | state: :pre_ai}
      # def handle_event(%AssemblyLine.Event{state: :pre_ai} = event) , do: %{event | state: :post_ai}
      # def handle_event(%AssemblyLine.Event{state: :post_ai} = event) , do: %{event | state: :complete}
      # def handle_event(%AssemblyLine.Event{state: :break} = event) , do: event
      # def handle_event(%AssemblyLine.Event{state: :complete} = event) , do: event
      # , handle_event: 1
      defoverridable steps: 0, init: 1, on_completion: 1
    end
  end

  def run(%AssemblyLine.Step{_private: %{is_arbitrary?: true}} = step, event) do
    runner(step, event)
  end

  def run({%AssemblyLine.Step{_private: %{is_arbitrary?: true}}, :async} = step, event) do
    GenStage.call(AssemblyLine.Async.Queue, {:notify, {step, event}}, 99999)
    {:cont, event}
  end

  def run({step, :async}, event) do
    step = step.init()
    GenStage.call(AssemblyLine.Async.Queue, {:notify, {step, event}}, 99999)
    {:cont, event}
  end

  def run(step, event) when is_atom(step) do
    step = step.init()
    runner(step, event)
  end

  def run_compiler(step, event) when is_atom(step) do
    step = %{
      step.init()
      | adapter: AssemblyLine.Adapters.Compiler,
        routing: %AssemblyLine.Adapters.Compiler{
          disable_step_hooks: true,
          disable_conversation_recording: true
        }
    }

    runner(step, event)
  end

  def runner(%AssemblyLine.Step{module: module} = step, acc_event) when is_atom(module) do
    if Map.has_key?(step.routing, :verbose), do: dbg(step)

    acc_event = %{
      acc_event
      | step: step,
        timestamp: DateTime.utc_now(),
        response_format: module.response_format(),
        break_word: module.break_word()
    }

    acc_event =
      acc_event
      |> acc_event.step.module.run_before_step()
      |> AssemblyLine.update_remote_thread()
      |> AssemblyLine.set_prerun_context()
      |> AssemblyLine.update_internal_thread()

    resp =
      acc_event
      |> step.adapter.run()

    case resp do
      {:ok, reply, acc_event} ->
        message = step.adapter.deserialize(acc_event, reply)
        AssemblyLine.Manager.circuit_break(acc_event, message)

      map when is_map(map) ->
        message = step.adapter.deserialize(acc_event, map)
        AssemblyLine.Manager.circuit_break(acc_event, message)

      string when is_binary(string) ->
        message = step.adapter.deserialize(acc_event, string)
        AssemblyLine.Manager.circuit_break(acc_event, message)

      {:error, error, _acc} ->
        if Map.has_key?(step.routing, :verbose), do: dbg(error)
        {:halt, :error}

      other_result ->
        IO.warn("Unexpected Result - Got back: #{other_result}")
        {:halt, :error}
    end
  end

  def circuit_break(%AssemblyLine.Event{break_word: break_word} = event, message)
      when break_word == message do
    event.step.module.on_failure(event)
    {:halt, :break}
  end

  def circuit_break(%AssemblyLine.Event{break_word: break_word} = event, message)
      when break_word != message do
    wrapped_message = event.step.adapter.wrap(event, "assistant", message)

    event =
      AssemblyLine.update_context(event, wrapped_message)
      |> AssemblyLine.set_response(wrapped_message)

    event = event.step.module.run_after_step(event)

    {:cont, event}
  end

  def event_check([]), do: raise("Pipeline must define at least one event.")
  def event_check(_steps), do: :ok
end
