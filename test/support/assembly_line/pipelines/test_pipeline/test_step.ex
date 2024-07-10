defmodule TestApp.Pipeline.TestPipeline.TestStep do
  use AssemblyLine.Step

  def prompt(%{assigns: assigns}) do
    """
    So far I have done: Fired Init on Pipeline: #{assigns.fired_init}
    """
  end

  # def prompt(_), do: "According to the building and fire code, what are the door lock requirements in this zone?"

  # def model, do: "gpt-4-1106-preview"
  def before_step(event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_before_step: true
      }
    )
  end

  def after_step(event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_after_step: true
      }
    )
    |> super()
  end

  def dial_agent(), do: {:test, :basic}
end
