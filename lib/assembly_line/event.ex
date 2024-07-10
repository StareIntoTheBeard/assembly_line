defmodule AssemblyLine.Event do
  use Accessible

  defstruct [
    :response,
    :assembly_line,
    :timestamp,
    :response_format,
    _private: %{caller_pid: nil, is_arbitrary?: false, remote_thread_id: nil, internal_thread_id: nil},
    step_list: [],
    step: %AssemblyLine.Step{},
    context: [],
    assigns: %{},
    break_word: "AI HALT REQUESTED"
  ]
end

# defmodule AssemblyLine.Step do
#   defstruct [
#     :adapter,
#     :module,
#     mapping: %AssemblyLine.FoundationModel{}
#   ]
# end

# %AssemblyLine.Event{
#   assembly_line: SomeAssemblyPipeline,
#   step: %AssemblyLine.Step{
#     adapter: AssemblyLine.Adapters.OpenAI,
#     module: SomeStep,
#     mapping: %AssemblyLine.FoundationModel{model: "openai-4-gpt-whatever"}
#   }

# }

# %AssemblyLine.Event{
#   assembly_line: SomeAssemblyPipeline,
#   step: %AssemblyLine.Step{
#     adapter: AssemblyLine.Adapters.OpenAI,
#     step: SomeStep,
#     mapping: %AssemblyLine.FoundationModel{model: "openai-4-gpt-whatever"}
#   }

# }
