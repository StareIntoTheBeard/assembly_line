defmodule AssemblyLine.Async.Queue do
  use GenStage

  def start_link(queue) do
    GenStage.start_link(__MODULE__, queue, name: __MODULE__)
  end

  def init(queue) do
    {:producer, queue}
  end

  def handle_demand(demand, queue) when demand > 0 do
    # If the queue is 3 and we ask for 2 items, we will
    # emit the items 3 and 4, and set the state to 5.
    demand = if demand > length(queue), do: -1, else: demand
    {events, queue} = Enum.split(queue, demand)
    {:noreply, events, queue}
  end

  def handle_call({:notify, {step, event}}, _from, state) do
    # Dispatch immediately
    {:reply, :ok, [{step, event}], state}
  end
end
