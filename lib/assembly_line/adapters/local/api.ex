defmodule AssemblyLine.Adapters.Local.Api do
  def request(%{message: message}) do
    # config = Application.get_all_env(:ex_aws)
    input_text =

    url =
      "http://localhost:12434/engines/llama.cpp/v1/chat/completions"
      headers = [
        {"accept", "application/json"},
        {"content-type", "application/json"}
      ]

      body = %{
        model: "ai/mistral",
        messages: [%{
          role: "user",
          content: message
        }]
      }
      |> Jason.encode!

    {:ok, %{body: body}} = HTTPoison.post(url, body, headers, timeout: :infinity, recv_timeout: :infinity)
    Jason.decode! body
  end
end
