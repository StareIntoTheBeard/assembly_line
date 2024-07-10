defmodule AssemblyLine.Async.Delegator do
  use GenStage

  def start_link(queue) do
    GenStage.start_link(__MODULE__, queue, name: __MODULE__)
  end

  def init(state) do
    {:producer_consumer, state, subscribe_to: [AssemblyLine.Async.Queue]}
  end

  def handle_events(events, _from, state) do
    events =
      Enum.map(events, fn {step, event} ->
        Task.start_link(fn ->
          AssemblyLine.Manager.runner(step, event)
        end)
      end)

    {:noreply, events, state}
  end
end
