defmodule AssemblyLineTest do
  use AssemblyLine.TestCase

  setup do
    event =
      %AssemblyLine.Event{}
      |> AssemblyLine.set_internal_thread()

    %{event: event}
  end

  test "init/1", %{event: event} do
    assert event ==
             AssemblyLine.init()
             |> AssemblyLine.reset_internal_thread(AssemblyLine.get_internal_thread(event))
  end

  test "set_assigns/2 for map assigns", %{event: event} do
    assigned_event = %{event | assigns: %{thing: "stuff"}}
    assert AssemblyLine.set_assigns(event, %{thing: "stuff"}) == assigned_event
    assigned_event_2 = %{event | assigns: %{stuff: "thing"}}
    assigned_event_2 = AssemblyLine.set_assigns(assigned_event_2, %{thing: "stuff"})
    assert assigned_event_2.assigns == %{thing: "stuff"}
  end

  test "update_assigns/2 for map assigns", %{event: event} do
    assigned_event = %{event | assigns: %{thing: "stuff"}}
    assigned_event = AssemblyLine.update_assigns(assigned_event, %{ok: "more"})

    assert assigned_event.assigns == %{
             thing: "stuff",
             ok: "more"
           }
  end

  test "execute/1 for an event", %{event: event} do
    executed_event =
      event
      |> AssemblyLine.update_assigns(%{
        test_step_default: false
      })
      |> TestApp.Pipeline.TestPipeline.execute()

    assert executed_event.assigns == %{
             fired_init: true,
             fired_before_step: :maybe,
             fired_after_step: true,
             next_step_default: "this was set",
             fired_before_next_step: true,
             fired_after_next_step: true,
             fired_on_completion: true,
             test_step_default: false,
             another_test_step_default: true,
             something_else: nil
           }

    assert executed_event.context == [
             %{content: "response from the run\n some other response", role: "assistant"},
             %{
               content:
                 "So far I have done: \n\nFired Init on Pipeline: true\nfired_before_step on Pipeline: maybe\nfired_after_step on Pipeline: true\ntest_step_default on Pipeline: false\nanother_test_step_default on Pipeline: true\nfired_before_next_step on Pipeline: true",
               role: "user"
             },
             %{content: "response from the run\n some other response", role: "assistant"},
             %{
               content:
                 "So far I have done: \n\nFired Init on Pipeline: true\nfired_before_step on Pipeline: maybe\ntest_step_default on Pipeline: false\nanother_test_step_default on Pipeline: true",
               role: "user"
             }
           ]
  end
end
