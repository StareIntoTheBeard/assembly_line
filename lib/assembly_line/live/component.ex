defmodule AssemblyLine.Live.Component do
  defmacro __using__(_) do
    quote do
      def handle_update(event, component_id, parameters) do
        Phoenix.LiveView.Channel.send_update(
          AssemblyLine.get_caller_pid(event),
          {__MODULE__, component_id},
          parameters
        )

        event
      end
    end
  end
end
