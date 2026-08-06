defmodule Intents.Resolver do
  @moduledoc """
  Slot resolver for intent pipelines.

  Public API:

    Intents.Resolver.resolve(event, pipeline_module)
      → {:ready, event} | {:gather, event}

  Flow:

    1. Compute the union of required attrs across all steps of pipeline_module.
       The system framework requires steps to declare their inputs via
       `attr(:foo, required: true)`. The pipeline's "required assigns" is
       just the union of every required attr across every step.

    2. Compute the GAP: required attrs not present (or nil) in event.assigns.

    3. If gap is empty → {:ready, event}. Caller proceeds to execute the
       pipeline.

    4. If gap is non-empty:
       a. Stash the gap on event.assigns.gather_attrs and run the Extract
          pipeline. The LLM extracts whatever the user has stated for the
          missing fields, across the full conversation.
       b. Merge extracted values back into the gap pool and recompute the gap.
       c. If gap is now empty → {:ready, event}.
       d. Otherwise → run the gather-reply pipeline to ask the user, then
          return {:gather, event}.

  Cross-turn persistence: callers (Intents.process/2 + LiveCallbacks)
  preserve the returned event on socket.assigns.assistant_event so extracted
  values survive into the next turn.
  """

  @doc """
  Returns {:ready, event} when every required assign of pipeline_module's
  steps is satisfied, or {:gather, event} when the caller should stop and
  wait for user input.

  pipeline_module must implement `steps/0` returning a list of step modules
  that use Assignable (which provides `__assignments__/0`).
  """
  @doc """
  For pipeline-driven (non-planner) intents. Asks each step in the pipeline
  what required assigns are missing from the event, then runs the
  extract→re-check→maybe-gather flow.
  """
  def resolve(event, pipeline_module) when is_atom(pipeline_module) do
    gap = current_gap(pipeline_module, event.assigns)
    dbg({:resolver_initial_gap, pipeline_module, gap})

    if gap == [] do
      {:ready, event}
    else
      event = run_extraction(event, gap)
      gap_after = current_gap(pipeline_module, event.assigns)
      dbg({:resolver_gap_after_extract, gap_after})

      cond do
        gap_after == [] ->
          {:ready, event}

        true ->
          event = run_compose_gather(event, gap_after)
          {:gather, event}
      end
    end
  end

  @doc """
  Like resolve/2 but takes an explicit list of required attr names. Used by
  the planner path where the gap comes from ToolSpecs, not from a pipeline
  module.
  """
  def resolve_for_gap(event, required) when is_list(required) do
    required = reject_resolver_internals(required)
    gap = compute_gap_from_list(event.assigns, required)
    dbg({:resolver_initial_gap, gap})

    if gap == [] do
      {:ready, event}
    else
      event = run_extraction(event, gap)
      gap_after = compute_gap_from_list(event.assigns, required)

      cond do
        gap_after == [] ->
          {:ready, event}

        true ->
          event = run_compose_gather(event, gap_after)
          {:gather, event}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Gap computation
  # ---------------------------------------------------------------------------

  # Uses each step's validate_assigns against the live event.assigns. The
  # framework's validate_assigns is the source of truth — same function
  # pipeline.compile/1 uses to fail-fast on missing assigns.
  defp current_gap(pipeline_module, assigns) do
    pipeline_module.steps()
    |> List.wrap()
    |> Enum.flat_map(&missing_from_step(&1, assigns))
    |> Enum.uniq()
    |> reject_resolver_internals()
  end

  defp missing_from_step(step, assigns) when is_atom(step) do
    case apply(step, :validate_assigns, [assigns, [should_raise: false]]) do
      %{missing_assignments: missing} -> missing
      _ -> []
    end
  end

  defp missing_from_step({step, _opts}, assigns), do: missing_from_step(step, assigns)

  # Manual check used by the planner path where the required list comes from
  # ToolSpecs (not a step). A key is "filled" if its value is non-nil,
  # non-empty-string, non-empty-list.
  defp compute_gap_from_list(assigns, required) do
    Enum.reject(required, fn key ->
      val = Map.get(assigns, key)
      not is_nil(val) and val != "" and val != []
    end)
  end

  # These are plumbing the Resolver itself sets up. They're never things to
  # ask the user about.
  @resolver_internals [
    :gather_attrs,
    :missing_attrs,
    :known_values,
    :extracted_values,
    :assistant_reply,
    :needs_user_input,
    :user_intent,
    :active_intent,
    :pipeline_module,
    :previous_messages,
    :latest_message,
    :current_user_id,
    :thread_owner_id,
    :current_internal_thread_id,
    :organization_id,
    :organization_ids,
    :current_page_context,
    :page_actions,
    :researched_arguments,
    :unresearched_arguments
  ]

  defp reject_resolver_internals(list) do
    Enum.reject(list, &(&1 in @resolver_internals))
  end

  # ---------------------------------------------------------------------------
  # Pipelines
  # ---------------------------------------------------------------------------

  defp run_extraction(event, gap) do
    event
    |> AssemblyLine.update_assigns(%{gather_attrs: gap})
    |> Bullhorn.AIPipeline.AssistantResolver.execute()
  end

  defp run_compose_gather(event, missing) do
    known =
      event.assigns
      |> Map.take(known_keys_from_extraction(event))
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == [] end)
      |> Map.new()

    event
    |> AssemblyLine.update_assigns(%{
      missing_attrs: missing,
      known_values: known
    })
    |> Bullhorn.AIPipeline.AssistantGatherReply.execute()
  end

  defp known_keys_from_extraction(event) do
    case Map.get(event.assigns, :extracted_values) do
      m when is_map(m) -> Map.keys(m)
      _ -> []
    end
  end
end
