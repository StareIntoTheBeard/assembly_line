defmodule AssemblyLine do
  ### client apis
  def init(), do: %AssemblyLine.Event{} |> update_internal_thread()
  def init(:arbitrary_pipeline), do: init() |> AssemblyLine.set_is_arbitrary?(true)

  def set_prerun_context(%AssemblyLine.Event{_private: %{is_arbitrary?: true}} = event) do
    message = event.step.module.adapter.wrap(event, "user", event.step.module.prompt(event))
    __MODULE__.update_context(event, message)
  end

  def set_prerun_context(%AssemblyLine.Event{} = event) do
    prompt =
      event
      |> event.step.module.prompt()

    message = event.step.module.adapter.wrap(event, "user", prompt)
    __MODULE__.update_context(event, message)
  end

  def add_step(event, step_module) do
    new_step_list = event.step_list ++ [step_module]
    put_in(event, [:step_list], new_step_list)
  end

  def get_step_list(%AssemblyLine.Event{_private: %{is_arbitrary?: true}} = event) do
    event.step_list
  end

  def get_step_list(event), do: event.assembly_line.steps()

  def update_context(%AssemblyLine.Event{} = event, []) do
    event
  end

  def update_context(%AssemblyLine.Event{} = event, context_element)
      when is_map(context_element) do
    NoSQL.Mongo.init()
    |> NoSQL.Mongo.insert_conversation(%{message: context_element, event: event})

    Map.put(event, :context, [context_element] ++ event.context)
  end

  def update_context(%AssemblyLine.Event{} = event, context_elements)
      when is_list(context_elements) do
    Map.put(event, :context, context_elements ++ event.context)
  end

  def update_remote_thread(event) do
    if is_nil(AssemblyLine.get_remote_thread(event)) do
      __MODULE__.set_remote_thread(event)
    else
      event
    end
  end

  def update_internal_thread(event) do
    if is_nil(AssemblyLine.get_internal_thread(event)) do
      __MODULE__.set_internal_thread(event)
    else
      event
    end
  end

  def set_remote_thread(%AssemblyLine.Event{} = event) do
    put_in(event, [:_private, :remote_thread_id], event.step.adapter.generate_thread())
  end

  def set_remote_thread(%AssemblyLine.Event{} = event, id) do
    put_in(event, [:_private, :remote_thread_id], id)
  end

  def get_remote_thread(%AssemblyLine.Event{} = event) do
    get_in(event, [:_private, :remote_thread_id])
  end

  def set_internal_thread(%AssemblyLine.Event{} = event) do
    put_in(event, [:_private, :internal_thread_id], UUID.uuid1())
  end

  def set_internal_thread(%AssemblyLine.Event{_private: %{internal_thread_id: id}} = event)
      when not is_nil(id) do
    event
  end

  def reset_internal_thread(%AssemblyLine.Event{} = event, id) do
    put_in(event, [:_private, :internal_thread_id], id)
  end

  def get_internal_thread(%AssemblyLine.Event{} = event) do
    get_in(event, [:_private, :internal_thread_id])
  end

  def update_caller_pid(%AssemblyLine.Event{} = event, pid) do
    put_in(event, [:_private, :caller_pid], pid)
  end

  def get_caller_pid(%AssemblyLine.Event{} = event) do
    get_in(event, [:_private, :caller_pid])
  end

  def set_is_arbitrary?(%AssemblyLine.Event{} = event, true) do
    put_in(event, [:_private, :is_arbitrary?], true)
  end

  def get_is_arbitrary?(%AssemblyLine.Event{} = event) do
    get_in(event, [:_private, :is_arbitrary?])
  end

  def set_assigns(%AssemblyLine.Event{} = event, assigns) when is_map(assigns),
    do: Map.put(event, :assigns, assigns)

  def update_assigns(%AssemblyLine.Event{} = event, assigns) when is_map(assigns) do
    event_assigns = Map.merge(event.assigns, assigns)
    set_assigns(event, event_assigns)
  end

  def set_response(%AssemblyLine.Event{} = event, response),
    do: Map.put(event, :response, response)

  def get_response(%AssemblyLine.Event{} = event) do
    %{"content" => response} = NoSQL.Mongo.find_last_response(event)
    response
  end

  # defp parse_response({key, value}) do
  #   key == :role && value == "assistant"
  # end

  # defp parse_response(%{role: role, content: _}) do
  #   role == "assistant"
  # end

  def get_next_user_prompt(%AssemblyLine.Event{context: context}) do
    context
    |> Enum.find(fn context_item ->
      parse_next_user_prompt(context_item)
    end)
  end

  defp parse_next_user_prompt({key, value}) do
    key == :role && value == "user"
  end

  defp parse_next_user_prompt(%{role: role, content: _}) do
    role == "user"
  end
end
