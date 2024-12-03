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

    ExAws.Bedrock.invoke_model(event.step.module.model, %{
      "prompt" => message
    })
    |> ExAws.request!(service_override: :bedrock, region: "us-west-2")
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
  end

  def wrap(%AssemblyLine.Event{} = _event, role, message),
    do: %{role: role, content: message}
end
