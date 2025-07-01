defmodule AssemblyLine.Changeset.CheckService do
  @behaviour AssemblyLine.Pipeline
  use AssemblyLine.Manager

  def steps() do
    [
      AssemblyLine.Changeset.Step.CheckService
    ]
  end
end
