defmodule AssemblyLine.Event do
  use Accessible

  defstruct [
    :response,
    :assembly_line,
    :timestamp,
    :response_format,
    _private: %{
      caller_pid: nil,
      is_arbitrary?: false,
      remote_thread_id: nil,
      internal_thread_id: nil
    },
    step_list: [],
    step: %AssemblyLine.Step{},
    context: [],
    assigns: %{},
    required_assigns: %{},
    break_word: "AI HALT REQUESTED"
  ]
end
