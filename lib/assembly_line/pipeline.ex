defmodule AssemblyLine.Pipeline do
  @callback init(struct()) :: struct()
  @callback steps() :: nonempty_list()
  @callback on_completion(struct()) :: term()
end
