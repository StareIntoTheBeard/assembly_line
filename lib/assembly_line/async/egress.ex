defmodule AssemblyLine.Async.Egress do
  use GenStage

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:consumer, %{batches: %{}}, subscribe_to: [AssemblyLine.Async.Delegator]}
  end

  def register_batch(batch_id, total, opts) do
    GenStage.cast(__MODULE__, {:register_batch, batch_id, total, opts})
  end

  def mark_completed(batch_id, result) do
    GenStage.cast(__MODULE__, {:mark_completed, batch_id, result})
  end

  def handle_cast({:register_batch, batch_id, total, opts}, state) do
    batch = %{
      total: total,
      completed: 0,
      failed: 0,
      thread_owner_id: opts[:thread_owner_id],
      thread_id: opts[:thread_id],
      organization_id: opts[:organization_id],
      blog_id: opts[:blog_id],
      redirect_url: opts[:redirect_url] || "/blogs/#{opts[:blog_id]}/articles"
    }

    {:noreply, [], put_in(state, [:batches, batch_id], batch)}
  end

  def handle_cast({:mark_completed, batch_id, result}, state) do
    case state.batches[batch_id] do
      nil ->
        {:noreply, [], state}

      batch ->
        batch = tally(batch, result)

        if batch.completed + batch.failed >= batch.total do
          broadcast_completion(batch)
          {:noreply, [], %{state | batches: Map.delete(state.batches, batch_id)}}
        else
          {:noreply, [], put_in(state, [:batches, batch_id], batch)}
        end
    end
  end

  def handle_events(_events, _from, state) do
    {:noreply, [], state}
  end

  defp tally(batch, :ok), do: %{batch | completed: batch.completed + 1}
  defp tally(batch, {:error, _}), do: %{batch | failed: batch.failed + 1}

  defp broadcast_completion(batch) do
    message = build_message(batch)

    Memories.reconcile_new_memory(
      message,
      :assistant,
      batch.thread_owner_id,
      batch.thread_id,
      batch.organization_id
    )

    Phoenix.PubSub.broadcast(
      Bullhorn.PubSub,
      "chat:#{batch.thread_owner_id}:#{batch.thread_id}",
      {:redirect_to_route,
       %{
         flash_message: message,
         redirect_url: batch.redirect_url
       }}
    )
  end

  defp build_message(%{total: total, completed: total, failed: 0}) do
    "All #{total} articles are ready."
  end

  defp build_message(%{completed: completed, failed: failed}) do
    "#{completed} articles created (#{failed} failed)."
  end
end
