defmodule AssemblyLine.Adapters.BedrockStability do
  use AssemblyLine.Adapter
  @enforce_keys [:model]
  defstruct [
    :model
  ]

  def run(event) do
    message =
      AssemblyLine.get_next_user_prompt(event)
      |> Map.get(:content)

    response =
      ExAws.Bedrock.invoke_model(event.step.module.model, %{
        "prompt" => message,
        "aspect_ratio" => "16:9"
      })
      |> ExAws.request!(service_override: :bedrock, region: "us-west-2")

    {:ok, response, event}
  end

  def deserialize(_event, %{"images" => [image]}) do
    temp_directory = System.tmp_dir()
    filename = "#{UUID.uuid4()}.png"
    written_path = "#{temp_directory}/#{filename}"
    content = Base.decode64!(image)
    :ok = File.write!(written_path, content)

    ExAws.S3.Upload.stream_file(written_path)
    |> ExAws.S3.upload("stability-temp-images", filename)
    |> ExAws.request!()
    |> get_in([:body, :location])

    {:ok, url} =
      ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, "stability-temp-images", filename)

    [url]
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
