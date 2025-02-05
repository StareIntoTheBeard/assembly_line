defmodule TestApp.Pipeline.TestPipeline.NextTestStep do
  use AssemblyLine.Step

  attr(:fired_init, default: false)
  attr(:test_step_default, default: :override_me)
  attr(:fired_before_step, default: :override_me)
  attr(:fired_after_step, default: :override_me)
  attr(:next_step_default, default: "this was set")

  return(:fired_before_next_step)
  return(:fired_after_next_step)

  def prompt(assigns) do
    ~H"""
    So far I have done: 

    Fired Init on Pipeline: {@fired_init}
    fired_before_step on Pipeline: {@fired_before_step}
    fired_after_step on Pipeline: {@fired_after_step}
    test_step_default on Pipeline: {@test_step_default}
    another_test_step_default on Pipeline: {@another_test_step_default}
    fired_before_next_step on Pipeline: {@fired_before_next_step}
    """
  end

  # def prompt(_), do: "According to the building and fire code, what are the door lock requirements in this zone?"

  # def model, do: "gpt-4-1106-preview"
  def before_step(event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_before_next_step: true
      }
    )
  end

  def after_step(event) do
    AssemblyLine.update_assigns(
      event,
      %{
        fired_after_next_step: true
      }
    )
    |> super()
  end

  def dial_agent(), do: {:test, :basic}
end
