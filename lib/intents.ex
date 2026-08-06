defmodule Intents do
  @intent_router Application.compile_env(:bullhorn, :intents_router)

  def process(event, router \\ @intent_router) do
    intent_object = Jason.decode!(event.response.content)

    %{
      "reply" => reply,
      "intent" => intent
    } = intent_object

    event =
      AssemblyLine.update_assigns(event, %{
        assistant_reply: reply,
        user_intent: intent,
        active_intent: intent
      })

    route = route?(intent, router)

    case route do
      {:no_route, nil, nil} ->
        act_on_intent({false, route, event}, reply)

      {intent_module, intent_func, metadata} ->
        case apply(intent_module, :fetch_permission, [intent_func, event]) do
          false ->
            act_on_intent({false, route, event}, reply)

          _ ->
            run_route(event, route, metadata, reply)
        end
    end
  end

  # Dispatch a permitted route. Three cases:
  #
  #   1. Conversational intent (no pipeline_module): just deliver triage's
  #      reply via intent_func.
  #   2. Pipeline that needs planning (search, navigate): Plan picks a tool
  #      → Resolver fills the tool's required args from ToolSpecs →
  #      execute_plan dispatches to Tools → intent's pipeline_module runs.
  #   3. Pipeline that doesn't plan (slot-gather case): Resolver fills the
  #      pipeline's required attrs → pipeline runs.
  #
  # Both paths use Resolver. Both call Resolver at most once per turn — if
  # info is missing, Resolver asks the user and the next turn re-enters
  # process/2 from the top.
  defp run_route(event, route, metadata, reply) do
    pipeline_module = Map.get(metadata, :pipeline_module)
    needs_planning = Map.get(metadata, :needs_planning, false)
    required_attrs = Map.get(metadata, :required_attrs, [])

    cond do
      # Planner-driven (search, navigate). Plan → Resolver → execute tool.
      needs_planning ->
        run_planner_path(event, route, metadata, reply)

      # Pipeline-driven slot-gather. Resolver introspects pipeline steps.
      not is_nil(pipeline_module) ->
        run_resolver_path(event, route, pipeline_module, reply)

      # Inline intent with declared required_attrs but no pipeline. Resolver
      # gathers values straight into event.assigns; intent_func does the
      # work. For intents whose work needs no LLM call beyond extraction.
      required_attrs != [] ->
        run_inline_path(event, route, required_attrs, reply)

      # Pure-chat intents — no resolver, no pipeline.
      true ->
        act_on_intent({true, route, event}, reply)
    end
  end

  # Slot-gather path: extract from conversation, check gap, validate, execute or ask.
  defp run_resolver_path(event, route, pipeline_module, reply) do
    {_, _, metadata} = route

    case Intents.Resolver.resolve(event, pipeline_module) do
      {:ready, event} ->
        event = AssemblyLine.update_assigns(event, %{needs_user_input: false})

        case run_validators(event, metadata) do
          :ok ->
            act_on_intent({true, route, event}, reply)

          {:errors, errors, field_values} ->
            event = run_suggest_alternatives(event, errors, field_values)
            hand_back_with_reply(event, route, reply)
        end

      {:gather, event} ->
        # Resolver wrote chat + set assistant_reply. Hand back through intent_func.
        hand_back_with_reply(event, route, reply)
    end
  end

  # Inline-path counterpart: same validation hook.
  defp run_inline_path(event, route, required_attrs, reply) do
    {_, _, metadata} = route

    case Intents.Resolver.resolve_for_gap(event, required_attrs) do
      {:ready, event} ->
        event = AssemblyLine.update_assigns(event, %{needs_user_input: false})

        case run_validators(event, metadata) do
          :ok ->
            {intent_module, intent_func, _meta} = route
            final_reply = Map.get(event.assigns, :assistant_reply, reply)
            apply(intent_module, intent_func, [final_reply, event])
            event

          {:errors, errors, field_values} ->
            event = run_suggest_alternatives(event, errors, field_values)
            hand_back_with_reply(event, route, reply)
        end

      {:gather, event} ->
        hand_back_with_reply(event, route, reply)
    end
  end

  # Validators are declared in intent metadata as a list of arity-1 functions
  # taking event.assigns and returning :ok | {:errors, %{field => message},
  # %{field => user_value}}. The third element is the user-given values for
  # the offending fields so SuggestAlternatives can hint at alternatives.
  defp run_validators(event, metadata) do
    validators = Map.get(metadata, :validators, [])

    Enum.reduce_while(validators, :ok, fn validator, _acc ->
      case validator.(event.assigns) do
        :ok -> {:cont, :ok}
        {:errors, errors, field_values} -> {:halt, {:errors, errors, field_values}}
      end
    end)
  end

  defp run_suggest_alternatives(event, errors, field_values) do
    event
    |> AssemblyLine.update_assigns(%{
      validation_errors: errors,
      validation_field_values: field_values
    })
    |> Bullhorn.AIPipeline.AssistantSuggestAlternatives.execute()
  end

  # Planner path: Plan picks a tool → Resolver fills its args (from ToolSpecs)
  # → execute the tool → run intent's pipeline_module. Each phase is one
  # LLM call; if anything's missing, Resolver asks the user and the next
  # user turn re-enters from the top.
  defp run_planner_path(event, route, metadata, reply) do
    dbg(:fuck)
    event = run_planner(event, metadata.pipeline_module)
    plan = Map.get(event.assigns, :plan)

    cond do
      # Planner needs more input from the user — already wrote chat in its
      # after_step. Hand the event back so the LV picks up assistant_reply.
      plan == "ask_user" ->
        {intent_module, intent_func, _meta} = route
        final_reply = Map.get(event.assigns, :assistant_reply, reply)
        apply(intent_module, intent_func, [final_reply, event])
        event

      is_binary(plan) and plan != "" ->
        gap =
          Bullhorn.AIPipeline.ToolSpecs.args_for(plan)
          |> dbg

        case Intents.Resolver.resolve_for_gap(event, gap) do
          {:ready, event} ->
            dbg(:shit)
            # Move resolved values into researched_arguments shape that
            # execute_plan/1 expects.
            dbg(event.assigns)

            researched =
              gap
              |> Enum.map(fn k -> {k, Map.get(event.assigns, k)} end)
              |> Map.new()
              |> Map.merge(event.assigns.researched_arguments)
              |> dbg

            event =
              event
              |> AssemblyLine.update_assigns(%{
                researched_arguments: researched,
                unresearched_arguments: %{},
                needs_user_input: false
              })

            case execute_plan(event) do
              {:ok, event} ->
                dbg(:altshit)
                act_on_intent({true, route, event}, reply)

              {:loop, event} ->
                # Tool reported missing fields. Add them to the gap and ask.
                extra = Map.get(event.assigns, :unresearched_arguments, %{}) |> Map.keys()

                case Intents.Resolver.resolve_for_gap(event, gap ++ extra) do
                  {:ready, event} ->
                    dbg(:unshit)

                    case execute_plan(event) do
                      {:ok, event} -> act_on_intent({true, route, event}, reply)
                      {:loop, event} -> hand_back_with_reply(event, route, reply)
                    end

                  {:gather, event} ->
                    dbg(:fuckshit)
                    hand_back_with_reply(event, route, reply)
                end
            end

          {:gather, event} ->
            dbg(:unfuck)
            hand_back_with_reply(event, route, reply)
        end

      true ->
        # Planner returned nothing usable. Treat as ask_user.
        msg = "I need a bit more info — can you clarify what you'd like?"

        event =
          AssemblyLine.update_assigns(event, %{assistant_reply: msg, needs_user_input: true})

        hand_back_with_reply(event, route, reply)
    end
  end

  defp hand_back_with_reply(event, route, reply) do
    {intent_module, intent_func, _meta} = route
    final_reply = Map.get(event.assigns, :assistant_reply, reply)
    apply(intent_module, intent_func, [final_reply, event])
    event
  end

  def route?(assumed_intent, router \\ @intent_router) do
    apply(router, :route, [assumed_intent])
  end

  defp run_planner(event, pipeline_module) do
    event
    |> AssemblyLine.update_assigns(%{pipeline_module: pipeline_module})
    |> Bullhorn.AIPipeline.Planner.execute()
  end

  defp execute_plan(event) do
    plan = event.assigns.plan |> to_string() |> String.trim_leading(":")
    Code.ensure_loaded(Tools)

    case apply(Tools, String.to_existing_atom(plan), [event.assigns.researched_arguments]) do
      # Navigation with resolved struct -> store url, struct, and update resolved_entities
      {:ok, [%{url: url, struct: struct} | _], _} ->
        {:ok,
         AssemblyLine.update_assigns(event, %{
           redirect_url: url,
           resolved_struct: struct,
           resolved_entities: merge_resolved_entity(event, struct),
           search_results: [struct]
         })}

      # Navigation with just a url (static route)
      {:ok, [%{url: url} | _], _} ->
        {:ok, AssemblyLine.update_assigns(event, %{redirect_url: url, search_results: []})}

      # Single tool result wrapping a struct (blog/article/org lookup)
      {:ok, [result], _count} when is_map(result) ->
        assigns =
          case result do
            %{struct: %{} = struct} ->
              %{
                search_results: [result],
                resolved_entities: merge_resolved_entity(event, struct)
              }
              |> maybe_add_blog_keys(struct)

            _ ->
              %{tool_result: result, search_results: [result]}
          end

        {:ok, AssemblyLine.update_assigns(event, assigns)}

      # No results
      {:ok, [], _} ->
        {:ok, AssemblyLine.update_assigns(event, %{tool_result: :not_found, search_results: []})}

      # Multiple results
      {:ok, [_ | _] = many, _} ->
        {:ok,
         AssemblyLine.update_assigns(event, %{
           tool_result: {:multiple, many},
           search_results: many
         })}

      # Planner picked a tool but required args weren't provided -> loop
      {:error, {:missing, fields_map}} ->
        unresearched =
          event.assigns
          |> Map.get(:unresearched_arguments, %{})
          |> normalize_to_map()
          |> Map.merge(normalize_to_map(fields_map))

        {:loop, AssemblyLine.update_assigns(event, %{unresearched_arguments: unresearched})}

      other ->
        {:ok, AssemblyLine.update_assigns(event, %{tool_error: other, search_results: []})}
    end
  end

  defp merge_resolved_entity(event, struct) do
    resolved = Map.get(event.assigns, :resolved_entities, %{})

    case struct do
      %Bullhorn.Blogs.Blog{} -> Map.put(resolved, :blog, struct)
      %Bullhorn.Articles.Article{} -> Map.put(resolved, :article, struct)
      %Bullhorn.Organizations.Organization{} -> Map.put(resolved, :organization, struct)
      _ -> resolved
    end
  end

  defp maybe_add_blog_keys(assigns, %Bullhorn.Blogs.Blog{} = blog) do
    assigns
    |> Map.put(:blog_id, blog.id)
    |> Map.put(:blog_slug, blog.slug)
  end

  defp maybe_add_blog_keys(assigns, _other), do: assigns

  defp normalize_to_map(m) when is_map(m), do: m
  defp normalize_to_map(l) when is_list(l), do: Map.new(l)

  defp act_on_intent({true, {intent_module, intent_func, metadata}, event}, reply) do
    dbg({intent_module, intent_func, Map.keys(event.assigns)})

    cond do
      waiting_for_user_input?(event) ->
        dbg(:waiting_for_user_input)
        apply(intent_module, intent_func, [reply, event])
        event

      true ->
        event =
          case Map.get(metadata, :pipeline_module) do
            nil -> event
            mod -> mod.execute(event)
          end

        final_reply = Map.get(event.assigns, :assistant_reply, reply)
        apply(intent_module, intent_func, [final_reply, event])
        event
    end
  end

  defp act_on_intent({_, {:no_route, nil, nil}, event}, reply) do
    {:error, :has_no_valid_route, reply}
  end

  defp act_on_intent({_, _, event}, reply) do
    dbg({nil, nil, Map.keys(event.assigns)})
    {:error, :failed_permission_check, reply}
  end

  defp waiting_for_user_input?(event) do
    needs_input = Map.get(event.assigns, :needs_user_input, false)
    unresearched = Map.get(event.assigns, :unresearched_arguments, %{})

    needs_input and unresearched != %{} and unresearched != []
  end
end
