defmodule AssemblyLine.PhoneBook do
  def fetch_agent({service, use_case}), do: init() |> get_in([service, use_case])
  defp init(), do: Application.get_env(:assembly_line, __MODULE__)
end
