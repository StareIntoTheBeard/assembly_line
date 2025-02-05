defmodule AssemblyLine.Async.Egress do
  use GenStage

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:consumer, :the_state_does_not_matter, subscribe_to: [AssemblyLine.Async.Delegator]}
  end

  def handle_events(_events, _from, state) do
    # finishes with stuff?
    {:noreply, [], state}
  end
end
