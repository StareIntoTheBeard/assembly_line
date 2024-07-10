defmodule AssemblyLine.Adapters.BedrockAgent.StreamProcessor do
  def decode(%HTTPoison.Response{body: body}) do
    body
    |> String.chunk(:printable)
    |> Enum.flat_map(fn blob ->
      decode_element(blob)
    end)
    |> List.first()
    |> process()
  end

  defp process(resp) when is_tuple(resp), do: elem(resp, 1)
  defp process(resp), do: resp

  defp decode_element("event" <> string) when is_binary(string) do
    string
    |> String.replace(~r/[^}]*$/, "")
    |> String.replace(~r/\}\}$/, "}")
    |> Jason.decode!()
  end

  defp decode_element(_foo), do: []
end
