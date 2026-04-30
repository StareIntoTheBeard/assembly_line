defmodule AssemblyLine.Adapters.OpenAIImage do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    {:ok, resp} =
      OpenAI.image_generations(
       [ model: event.step.module().model,
        prompt: message,
        size: "1536x1024"],
        %OpenAI.Config{http_options: [recv_timeout: 120_000]}
      )

    {:ok, resp, event}
  end

  def deserialize(_event, %{data: [%{"b64_json" => b64_image}]}) do
    temp_directory = System.tmp_dir()
    filename = "#{UUID.uuid4()}.png"
    written_path = "#{temp_directory}/#{filename}"
    {:ok, content} = Base.decode64(b64_image)
    :ok = File.write!(written_path, content)

    ExAws.S3.Upload.stream_file(written_path)
    |> ExAws.S3.upload("stability-temp-images", filename)
    |> ExAws.request!()
    |> get_in([:body, :location])

    {:ok, url} =
      ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, "stability-temp-images", filename)

    [url]
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message), do: %{role: role, content: message}
end
