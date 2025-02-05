defmodule TestApp.Pipeline.TestPipeline do
  @behaviour AssemblyLine.Pipeline
  use AssemblyLine.Manager

  def steps() do
    [
      TestApp.Pipeline.TestPipeline.TestStep,
      TestApp.Pipeline.TestPipeline.NextTestStep
    ]
  end

  def init(%AssemblyLine.Event{} = event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_init: true
      }
    )
  end

  def on_completion(%AssemblyLine.Event{} = event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_on_completion: true
      }
    )
    |> super()
  end
end
