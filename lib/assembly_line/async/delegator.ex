defmodule AssemblyLine.Async.Delegator do
  use GenStage

  @default_max_concurrency 5

  def start_link(state) do
    GenStage.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    max = max_concurrency()

    {:producer_consumer, state,
     subscribe_to: [
       {AssemblyLine.Async.Queue, max_demand: max, min_demand: 1}
     ]}
  end

  def handle_events(events, _from, state) do
    events
    |> Task.async_stream(
      fn {pipeline, event} -> pipeline.execute(event) end,
      max_concurrency: max_concurrency(),
      timeout: :infinity,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.run()

    {:noreply, [], state}
  end

  defp max_concurrency do
    Application.get_env(:assembly_line, __MODULE__, [])
    |> Keyword.get(:max_concurrency, @default_max_concurrency)
  end
end
