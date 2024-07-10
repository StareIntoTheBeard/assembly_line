defmodule AssemblyLine.Live.Event do
  defmacro init() do
    quote do
      AssemblyLine.init()
      |> AssemblyLine.update_caller_pid(self())
    end
  end
end
