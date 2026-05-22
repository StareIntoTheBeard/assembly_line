defmodule AssemblyLine.Async.Egress do
  @moduledoc """
  Aggregates batch completion signals from async pipeline children. When the
  last child finishes, dispatches a side effect based on the batch's :kind:
    - :articles          → redirect to blog articles page + summary message
    - :images_scatter    → broadcast {asset_id, insert_after} pairs to editor
    - :images_standalone → redirect to first asset's show page
  """

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
      kind: opts[:kind] || :articles,
      total: total,
      completed: 0,
      failed: 0,
      results: [],
      thread_owner_id: opts[:thread_owner_id],
      thread_id: opts[:thread_id],
      organization_id: opts[:organization_id],
      blog_id: opts[:blog_id],
      article_id: opts[:article_id]
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

  def handle_events(_events, _from, state), do: {:noreply, [], state}

  defp tally(batch, :ok) do
    %{batch | completed: batch.completed + 1, results: [:ok | batch.results]}
  end

  defp tally(batch, {:ok, value}) do
    %{batch | completed: batch.completed + 1, results: [{:ok, value} | batch.results]}
  end

  defp tally(batch, {:error, reason}) do
    %{batch | failed: batch.failed + 1, results: [{:error, reason} | batch.results]}
  end

  # --- Articles ---
  defp broadcast_completion(%{kind: :articles, blog_id: blog_id} = batch) do
    message = build_articles_message(batch)
    write_to_chat(batch, message)

    Phoenix.PubSub.broadcast(
      Bullhorn.PubSub,
      "chat:#{batch.thread_owner_id}:#{batch.thread_id}",
      {:redirect_to_route,
       %{
         flash_message: message,
         redirect_url: "/blogs/#{blog_id}/articles"
       }}
    )
  end

  # --- Image scatter (article editor) ---
  defp broadcast_completion(%{kind: :images_scatter} = batch) do
    require Logger

    items =
      batch.results
      |> Enum.reverse()
      |> Enum.flat_map(fn
        {:ok, %{asset_id: id, insert_after: snippet}} ->
          [%{asset_id: id, insert_after: snippet}]

        _ ->
          []
      end)

    message = build_images_message(batch)
    write_to_chat(batch, message)

    # Persist once here so every LV in the shared chat thread gets a
    # consistent, already-saved state rather than each racing to save the
    # same content. LVs receive the broadcast and only update their view.
    {new_content, tagged_resources} =
      try do
        article = Bullhorn.Articles.get_article!(batch.article_id)
        new_content = Bullhorn.Articles.ImageInjector.inject(article.content || "", items)
        tagged_resources = Bullhorn.Articles.ImageInjector.tagged_resources(items)

        if article.content != new_content do
          Bullhorn.Articles.Article.create_revision(article, %{content: new_content})
        end

        case Bullhorn.Articles.update_article_with_possible_redirect(
               article,
               %{content: new_content}
             ) do
          {:ok, _updated} -> :ok
          other -> Logger.error("[egress :images_scatter] save failed: #{inspect(other)}")
        end

        {new_content, tagged_resources}
      rescue
        e ->
          Logger.error(
            "[egress :images_scatter] persist raised: " <>
              Exception.format(:error, e, __STACKTRACE__)
          )

          {nil, []}
      end

    Phoenix.PubSub.broadcast(
      Bullhorn.PubSub,
      "chat:#{batch.thread_owner_id}:#{batch.thread_id}",
      {:insert_images_into_editor,
       %{
         article_id: batch.article_id,
         content: new_content,
         tagged_resources: tagged_resources
       }}
    )
  end

  # --- Standalone image generation ---
  defp broadcast_completion(%{kind: :images_standalone} = batch) do
    first_asset_id =
      batch.results
      |> Enum.reverse()
      |> Enum.find_value(fn
        {:ok, %{asset_id: id}} -> id
        _ -> nil
      end)

    message = build_images_message(batch)
    write_to_chat(batch, message)

    if first_asset_id do
      Phoenix.PubSub.broadcast(
        Bullhorn.PubSub,
        "chat:#{batch.thread_owner_id}:#{batch.thread_id}",
        {:redirect_to_route,
         %{
           flash_message: message,
           redirect_url: "/assets/#{first_asset_id}"
         }}
      )
    end
  end

  defp write_to_chat(batch, message) do
    Memories.reconcile_new_memory(
      message,
      :assistant,
      batch.thread_owner_id,
      batch.thread_id,
      batch.organization_id
    )
  end

  defp build_articles_message(%{total: total, completed: total, failed: 0}) do
    "All #{total} articles are ready."
  end

  defp build_articles_message(%{completed: completed, failed: failed}) do
    "#{completed} articles created (#{failed} failed)."
  end

  defp build_images_message(%{total: total, completed: total, failed: 0}) do
    "All #{total} images are ready."
  end

  defp build_images_message(%{completed: completed, failed: failed}) do
    "#{completed} images created (#{failed} failed)."
  end
end
