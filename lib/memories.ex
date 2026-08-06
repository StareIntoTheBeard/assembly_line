defmodule Memories do
  @max_items 100

  # ============================================================================
  # FETCH
  # ============================================================================

  def fetch_conversation(user_id, internal_thread_id \\ nil)

  def fetch_conversation(user_id, nil) do
    loaded_memory =
      Memento.transaction(fn ->
        Memento.Query.select(
          Memory.Item,
          [{:==, :user_id, user_id}, {:==, :type, :conversation_item}]
        )
      end)

    case loaded_memory do
      {:ok, memory} -> Enum.sort_by(memory, & &1.timestamp, {:asc, DateTime})
      _ -> []
    end
  end

  def fetch_conversation(user_id, internal_thread_id) do
    loaded_memory =
      Memento.transaction(fn ->
        Memento.Query.select(
          Memory.Item,
          [
            {:==, :user_id, user_id},
            {:==, :type, :conversation_item},
            {:==, :internal_thread_id, internal_thread_id}
          ]
        )
      end)

    case loaded_memory do
      {:ok, memory} -> Enum.sort_by(memory, & &1.timestamp, {:asc, DateTime})
      _ -> []
    end
  end

  def fetch_conversation_for_viewer(user_id, internal_thread_id, viewer_id) do
    user_id
    |> fetch_conversation(internal_thread_id)
    |> Enum.filter(&visible_to?(&1, viewer_id))
  end

  def fetch_full_context(user_id, internal_thread_id) do
    loaded_memory =
      Memento.transaction(fn ->
        Memento.Query.select(
          Memory.Item,
          [{:==, :user_id, user_id}, {:==, :internal_thread_id, internal_thread_id}]
        )
      end)

    case loaded_memory do
      {:ok, memory} -> Enum.sort_by(memory, & &1.timestamp, {:asc, DateTime})
      _ -> []
    end
  end

  def fetch_full_context_for_viewer(user_id, internal_thread_id, viewer_id) do
    user_id
    |> fetch_full_context(internal_thread_id)
    |> Enum.filter(&visible_to?(&1, viewer_id))
  end

  defp visible_to?(%{shared_with: nil}, _viewer_id), do: true
  defp visible_to?(%{shared_with: []}, _viewer_id), do: true
  defp visible_to?(%{shared_with: list}, viewer_id) when is_list(list), do: viewer_id in list
  defp visible_to?(_, _), do: true

  # ============================================================================
  # ACTIVE STATE
  # ============================================================================

  def get_active_conversation(user_id) do
    user_id
    |> lookup_memory_pid_for_user_id()
    |> call({:get_active_conversation, user_id})
  end

  # ============================================================================
  # WRITES & REDUCTIONS
  # ============================================================================

  def refresh_memory(first_new_memory, from, user_id, internal_thread_id, organization_id) do
    reduction = __MODULE__.reduce(user_id, internal_thread_id, organization_id)
    __MODULE__.flush(reduction, user_id, internal_thread_id)
    __MODULE__.update_memory(first_new_memory, from, user_id, internal_thread_id)
  end

  def reconcile_new_memory(memory, from, user_id, internal_thread_id, organization_id) do
    reconcile_new_memory(memory, from, user_id, internal_thread_id, organization_id, [], user_id)
  end

  def reconcile_new_memory(
        memory,
        from,
        user_id,
        internal_thread_id,
        organization_id,
        extra_user_ids
      )
      when is_list(extra_user_ids) do
    reconcile_new_memory(
      memory,
      from,
      user_id,
      internal_thread_id,
      organization_id,
      extra_user_ids,
      user_id
    )
  end

  def reconcile_new_memory(
        memory,
        from,
        user_id,
        internal_thread_id,
        organization_id,
        extra_user_ids,
        sender_user_id
      )
      when is_list(extra_user_ids) do
    count =
      user_id
      |> fetch_conversation(internal_thread_id)
      |> length()

    if count >= @max_items do
      refresh_memory(memory, from, user_id, internal_thread_id, organization_id)
    else
      __MODULE__.update_memory(
        memory,
        from,
        user_id,
        internal_thread_id,
        extra_user_ids,
        sender_user_id
      )
    end
  end

  def reduce(user_id, internal_thread_id, organization_id) do
    user_id
    |> lookup_memory_pid_for_user_id()
    |> call({:reduce_conversation, user_id, internal_thread_id, organization_id})
  end

  def update_memory(memory, from, user_id, internal_thread_id) do
    update_memory(memory, from, user_id, internal_thread_id, [], user_id)
  end

  def update_memory(memory, from, user_id, internal_thread_id, extra_user_ids)
      when is_list(extra_user_ids) do
    update_memory(memory, from, user_id, internal_thread_id, extra_user_ids, user_id)
  end

  def update_memory(memory, from, user_id, internal_thread_id, extra_user_ids, sender_user_id)
      when is_list(extra_user_ids) do
    user_id
    |> lookup_memory_pid_for_user_id()
    |> cast(
      {:update_memory, memory, from, user_id, internal_thread_id, extra_user_ids, sender_user_id}
    )
  end

  def tick_page(context_string, user_id, internal_thread_id) do
    user_id
    |> lookup_memory_pid_for_user_id()
    |> cast({:tick_page, context_string, user_id, internal_thread_id})
  end

  def flush(reduction, user_id, internal_thread_id) do
    user_id
    |> lookup_memory_pid_for_user_id()
    |> cast({:flush, reduction, user_id, internal_thread_id})
  end

  # ============================================================================
  # CAST / CALL DISPATCH
  # ============================================================================

  defp cast(nil, {:reduce_conversation, user_id, internal_thread_id, _org_id} = message) do
    pid = start_pid_for(user_id, internal_thread_id)
    cast(pid, message)
  end

  defp cast(
         nil,
         {:update_memory, _msg, _from, user_id, internal_thread_id, _extras, _sender} = message
       ) do
    pid = start_pid_for(user_id, internal_thread_id)
    cast(pid, message)
  end

  defp cast(nil, {:update_memory, _msg, _from, user_id, internal_thread_id, _extras} = message) do
    pid = start_pid_for(user_id, internal_thread_id)
    cast(pid, message)
  end

  defp cast(nil, message) do
    [internal_thread_id, user_id | _] = message |> Tuple.to_list() |> Enum.reverse()
    pid = start_pid_for(user_id, internal_thread_id)
    cast(pid, message)
  end

  defp cast(pid, message), do: send(pid, message)

  defp call(nil, {:reduce_conversation, user_id, internal_thread_id, _org_id} = message) do
    pid = start_pid_for(user_id, internal_thread_id)
    call(pid, message)
  end

  defp call(nil, message) do
    [internal_thread_id, user_id | _] = message |> Tuple.to_list() |> Enum.reverse()
    pid = start_pid_for(user_id, internal_thread_id)
    call(pid, message)
  end

  defp call(pid, message), do: GenServer.call(pid, message)

  defp start_pid_for(user_id, internal_thread_id) do
    case Framework.MemoryServiceOTPServer.start(%{
           user_id: user_id,
           internal_thread_id: internal_thread_id
         }) do
      {:ok, pid} -> pid
      {:normal_exit, pid} -> pid
    end
  end

  def lookup_memory_pid_for_user_id(user_id) do
    result =
      Horde.Registry.select(Framework.MemoryServiceRegistry, [
        {
          {:"$1", :"$2", :"$3"},
          [],
          [{{:"$2", :"$3"}}]
        }
      ])
      |> Enum.filter(&(Map.get(elem(&1, 1), :id) == user_id))
      |> List.first()

    case result do
      {pid, _} -> pid
      _ -> nil
    end
  end
end
