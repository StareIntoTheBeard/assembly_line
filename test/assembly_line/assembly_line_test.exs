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
end
