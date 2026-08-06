defmodule Intents.LiveCallbacks do
  defmacro __using__(_opts) do
    quote do
      require AssemblyLine.Live.Event
      @before_compile Intents.LiveCallbacks
      @conversation_fetch_interval 1000 * 60 * 1

      def assistant_event,
        do:
          AssemblyLine.Live.Event.init()
          |> AssemblyLine.update_assigns(%{page_actions: __MODULE__.actions()})

      # Deferred page-context tick. mount_conversation (in on_mount) schedules
      # this via send(self(), {:tick_page_after_mount, params}) so the LV's
      # mount/3 has finished populating assigns by the time we read them.
      def handle_info({:tick_page_after_mount, params}, socket) do
        context_string =
          if function_exported?(socket.view, :page_context, 2) do
            try do
              socket.view.page_context(socket.assigns, params)
            rescue
              _ -> "Page: #{socket.view |> Module.split() |> List.last()}"
            end
          else
            "Page: #{socket.view |> Module.split() |> List.last()}"
          end

        Memories.tick_page(
          context_string,
          socket.assigns.current_user.id,
          socket.assigns.current_internal_thread_id
        )

        {:noreply, socket}
      end

      def handle_info({:conversate, reply, _event}, socket) do
        event =
          socket.assigns.assistant_event
          |> AssemblyLine.update_assigns(%{
            actions: @actions,
            previous_messages: socket.assigns.full_conversation_context,
            latest_message: reply
          })

        socket =
          socket
          |> start_async(:return_conversate, fn ->
            Bullhorn.AIPipeline.AssistantConversator.execute(event)
          end)

        {:noreply, socket}
      end

      @impl true
      def handle_info({:create_basic_article, reply, event}, socket) do
        current_user_id = socket.assigns.current_user.id

        event =
          event
          |> AssemblyLine.update_assigns(%{
            previous_messages: socket.assigns.full_conversation_context,
            latest_message: reply,
            current_user_id: current_user_id
          })

        socket =
          start_async(socket, :no_opp, fn ->
            if event.assigns[:blog_id] do
              Bullhorn.AIPipeline.AssistantCreateBasicArticle.execute(event)
            else
              event
            end
          end)

        {:noreply, socket}
      end

      @impl true
      def handle_info({:create_basic_article_batch, reply, event}, socket) do
        current_user_id = socket.assigns.current_user.id

        event =
          event
          |> AssemblyLine.update_assigns(%{
            previous_messages: socket.assigns.full_conversation_context,
            latest_message: reply,
            current_user_id: current_user_id
          })

        socket =
          start_async(socket, :no_opp, fn ->
            if event.assigns[:blog_id] do
              Bullhorn.AIPipeline.AssistantCreateBasicArticleBatch.execute(event)
            else
              event
            end
          end)

        {:noreply, socket}
      end

      # The framework's act_on_intent already runs AssistantGenerateImages via
      # the intent definition's pipeline_module. This handler exists only to
      # complete the intent function's send-to-caller_pid contract; running
      # the pipeline here would duplicate every batch.
      @impl true
      def handle_info({:generate_images, _reply, _event}, socket) do
        {:noreply, socket}
      end

      # Lock / unlock the article editor in response to PubSub broadcasts from
      # the agent. All participants in the shared chat thread who are viewing
      # the same article lock together so concurrent edits don't conflict with
      # the agent's in-flight content modifications.
      # Lock the editor for the current article via the existing disable-editor
      # JS event. Unlock happens implicitly when {:insert_images_into_editor}
      # pushes update-editor-content (the hook re-enables on that event).
      def handle_info({:editor_locked, true, article_id}, socket) do
        if socket.assigns[:article] && socket.assigns.article.id == article_id do
          {:noreply,
           socket
           |> assign(editor_locked: true)
           |> push_event("disable-editor", %{})}
        else
          {:noreply, socket}
        end
      end

      def handle_info({:editor_locked, false, _article_id}, socket) do
        {:noreply, assign(socket, editor_locked: false)}
      end

      # Egress has already persisted the new content + created a revision.
      # Each subscriber in the shared chat thread receives this and updates
      # only its view. No persistence, no revision creation — single source
      # of truth lives in Egress.
      def handle_info({:insert_images_into_editor, payload}, socket) do
        %{article_id: article_id, content: new_content, tagged_resources: tagged_resources} =
          payload

        cond do
          is_nil(new_content) ->
            {:noreply, assign(socket, agent_thinking: false, editor_locked: false)}

          socket.assigns[:article] && socket.assigns.article.id == article_id ->
            # Match setup-content's @content shape (tokens stripped) so the
            # AI pipelines (article_review, article_updater, etc) get clean
            # text context. Tokens stay in the editor via setContent.
            content_for_assigns = String.replace(new_content, ~r/\{\{[^}]+\}\}/, "")

            socket =
              socket
              |> assign(
                agent_thinking: false,
                editor_locked: false,
                content: content_for_assigns,
                original_content: content_for_assigns,
                dirty?: false
              )
              |> push_event("update-editor-content", %{content: new_content})
              |> push_event("render-content", %{
                tagged_resources: Jason.encode!(tagged_resources)
              })

            {:noreply, socket}

          true ->
            {:noreply, assign(socket, agent_thinking: false, editor_locked: false)}
        end
      end

      @impl true
      def handle_info(
            {:redirect_to_route_no_flash, %{redirect_url: redirect_url}},
            socket
          ) do
        {:noreply, push_navigate(socket, to: redirect_url)}
      end

      def handle_info({:write_to_chat, %{message: message, from: from}}, socket) do
        Memories.update_memory(
          message,
          from,
          socket.assigns.current_user.id,
          socket.assigns.current_internal_thread_id
        )

        conversation = (socket.assigns[:conversation] || []) ++ [%{message: message, from: from}]
        {:noreply, assign(socket, conversation: conversation, agent_thinking: false)}
      end

      def handle_info(:refresh_conversation, socket) do
        conversation = Memories.fetch_conversation(socket.assigns.current_user.id)
        Process.send_after(self(), :refresh_conversation, @conversation_fetch_interval)
        {:noreply, assign(socket, conversation: conversation)}
      end

      @impl true
      def handle_info(
            {:create_organization, _reply, event},
            socket
          ) do
        org_name =
          event.response.content
          |> Jason.decode!()
          |> Map.get("name", "")

        result =
          Bullhorn.Organizations.Organization.changeset(%Bullhorn.Organizations.Organization{}, %{
            name: org_name,
            slug: Bullhorn.Organizations.Organization.generate_slug(org_name),
            memberships: [%{user_id: socket.assigns.current_user.id, permission_level: 2}]
          })
          |> Bullhorn.Repo.insert()

        case result do
          {:ok, _organization} ->
            socket =
              socket
              |> push_navigate(to: ~p"/organizations")
              |> put_flash(:info, "Organization created.")

            {:noreply, socket}

          {:error, _changeset} ->
            socket =
              socket
              |> put_flash(:error, "This name was already taken.")

            {:noreply, socket}
        end
      end

      @impl true
      def handle_info(
            {:redirect_to_route, %{flash_message: flash_message, redirect_url: redirect_url}},
            socket
          ) do
        socket =
          put_flash(socket, :info, flash_message)
          |> assign(agent_thinking: false)
          |> push_navigate(to: redirect_url)

        {:noreply, socket}
      end

      @impl true
      def handle_info({:search_results_ready, _event}, socket) do
        {:noreply, socket}
      end

      def handle_info(:conversation_updated, socket) do
        owner_id = socket.assigns[:thread_owner_id] || socket.assigns.current_user.id

        conversation =
          Memories.fetch_conversation_for_viewer(
            owner_id,
            socket.assigns.current_internal_thread_id,
            socket.assigns.current_user.id
          )

        {:noreply, assign(socket, conversation: conversation)}
      end

      def handle_info(:thread_reset, socket) do
        user_id = socket.assigns.current_user.id

        new_thread_id =
          NoSQL.Mongo.get_last_internal_thread_id_for_user_id(user_id)

        conversation = Memories.fetch_conversation_for_viewer(user_id, new_thread_id, user_id)

        previous_reductions =
          Bullhorn.MemoryReductions.get_last_memory_reductions_visible_to_user(user_id)

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.unsubscribe(
            Bullhorn.PubSub,
            "chat:#{user_id}:#{socket.assigns.current_internal_thread_id}"
          )

          Phoenix.PubSub.subscribe(Bullhorn.PubSub, "chat:#{user_id}:#{new_thread_id}")
        end

        socket =
          assign(socket,
            conversation: conversation,
            current_internal_thread_id: new_thread_id,
            previous_reductions: previous_reductions
          )

        {:noreply, socket}
      end

      @doc """
      Broadcast from the agent when a redirect should happen. Navigate every
      participant who can see this redirect — including the originator and the
      thread owner. The originator's own handle_async may also navigate them;
      pushing the same URL twice is a harmless no-op, so we no longer rely on
      handle_async being the sole path (it isn't when the pipeline runs
      off-process under another participant's action).
      """
      def handle_info({:follow_redirect, url, shared_with, originator_id}, socket) do
        viewer_id = socket.assigns.current_user.id
        owner_id = socket.assigns[:thread_owner_id] || viewer_id

        if viewer_id == originator_id or viewer_id == owner_id or viewer_id in shared_with do
          dbg("viewer_id")
          dbg(viewer_id)
          {:noreply, push_navigate(assign(socket, agent_thinking: false), to: url)}
        else
          {:noreply, socket}
        end
      end

      def handle_info({:render_flush, {_, event}}, socket) do
        {:noreply, do_render_flush(event, socket)}
      end

      def handle_info({:participant_joined, _joined_user_id, _handle}, socket) do
        owner_id = socket.assigns[:thread_owner_id] || socket.assigns.current_user.id
        thread_id = socket.assigns.current_internal_thread_id

        conversation =
          Memories.fetch_conversation_for_viewer(
            owner_id,
            thread_id,
            socket.assigns.current_user.id
          )

        {:noreply,
         assign(socket,
           conversation: conversation,
           participants_map:
             Bullhorn.ThreadInvitations.participants_map_for_thread(owner_id, thread_id)
         )}
      end

      def handle_info({:participant_left, _left_user_id, _handle}, socket) do
        owner_id = socket.assigns[:thread_owner_id] || socket.assigns.current_user.id
        thread_id = socket.assigns.current_internal_thread_id

        conversation =
          Memories.fetch_conversation_for_viewer(
            owner_id,
            thread_id,
            socket.assigns.current_user.id
          )

        {:noreply,
         assign(socket,
           conversation: conversation,
           participants_map:
             Bullhorn.ThreadInvitations.participants_map_for_thread(owner_id, thread_id)
         )}
      end

      def handle_event("toggle_page_actions", _, socket) do
        {:noreply, assign(socket, show_page_actions: !socket.assigns.show_page_actions)}
      end

      def handle_event("mention_search", %{"query" => ""}, socket) do
        {:noreply, assign(socket, mention_results: [])}
      end

      def handle_event("mention_search", %{"query" => query}, socket) do
        current_user_id = socket.assigns.current_user.id
        org_ids = Enum.map(socket.assigns.current_user.organizations, & &1.id)

        raw_matches = Bullhorn.Accounts.search_users_for_mention(query, org_ids)
        matches = Enum.reject(raw_matches, &(&1.id == current_user_id))

        mention_results =
          matches
          |> Enum.map(fn user ->
            %{
              id: user.id,
              handle: Bullhorn.Accounts.handle_for(user),
              email: user.email
            }
          end)
          |> then(fn list ->
            [%{id: "agent", handle: "quip", email: "AI assistant"} | list]
          end)

        {:noreply, assign(socket, mention_results: mention_results)}
      end

      def handle_event("create_basic_article", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent("Help me create a basic article", assigns)

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      def handle_event("create_basic_article_batch", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent(
            "Help me create multiple articles in bulk",
            assigns
          )

        event =
          event
          |> AssemblyLine.update_assigns(%{
            organization_id: assigns.current_organization.id,
            current_internal_thread_id: assigns.current_internal_thread_id,
            thread_owner_id: assigns[:thread_owner_id] || assigns.current_user.id,
            blog_id: assigns[:blog] && assigns.blog.id
          })

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      def handle_event("generate_images", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent("Help me generate some images", assigns)

        event =
          event
          |> AssemblyLine.update_assigns(
            Map.merge(
              %{
                organization_id: assigns.current_organization.id,
                current_internal_thread_id: assigns.current_internal_thread_id,
                thread_owner_id: assigns[:thread_owner_id] || assigns.current_user.id
              },
              article_context_assigns(assigns)
            )
          )

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      def handle_event("change_to_different_page", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent("Take me to a different page", assigns)

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      @doc """
      Switch the chat sidebar into a different thread. Used when the user clicks a
      shared thread in the sidebar.

      Validates the user is an accepted participant before switching. Unsubscribes
      from the current thread's chat topic and subscribes to the new one.
      """
      def handle_event("switch_to_thread", %{"thread-id" => thread_id}, socket) do
        user_id = socket.assigns.current_user.id

        case Bullhorn.ThreadInvitations.get_active_participation(user_id, thread_id) do
          nil ->
            if thread_id == socket.assigns.current_internal_thread_id do
              {:noreply, socket}
            else
              own_last =
                NoSQL.Mongo.get_last_internal_thread_id_for_user_id(user_id)

              if thread_id == own_last do
                switch_to(socket, thread_id, user_id, false)
              else
                {:noreply, socket}
              end
            end

          invitation ->
            owner_id = invitation.invited_by_user_id
            switch_to(socket, thread_id, owner_id, true)
        end
      end

      defp switch_to(socket, thread_id, owner_id, is_guest?) do
        user_id = socket.assigns.current_user.id
        current_thread_id = socket.assigns.current_internal_thread_id
        current_owner_id = socket.assigns.thread_owner_id

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.unsubscribe(
            Bullhorn.PubSub,
            "chat:#{current_owner_id}:#{current_thread_id}"
          )

          Phoenix.PubSub.subscribe(Bullhorn.PubSub, "chat:#{owner_id}:#{thread_id}")
        end

        conversation =
          Memories.fetch_conversation_for_viewer(owner_id, thread_id, user_id)

        new_event =
          socket.view.assistant_event()
          |> AssemblyLine.set_internal_thread(thread_id)

        socket =
          assign(socket,
            current_internal_thread_id: thread_id,
            thread_owner_id: owner_id,
            is_guest_in_thread: is_guest?,
            conversation: conversation,
            assistant_event: new_event,
            participants_map:
              Bullhorn.ThreadInvitations.participants_map_for_thread(owner_id, thread_id),
            viewing_thread_id: nil,
            viewing_thread_messages: []
          )

        {:noreply, socket}
      end

      def handle_event("clean_conversation", event, socket) do
        old_thread = socket.assigns.current_internal_thread_id
        user_id = socket.assigns.current_user.id
        organization_id = socket.assigns.current_organization.id

        old_conversation = Memories.fetch_conversation(user_id, old_thread)

        if old_conversation != [] do
          reduction = Memories.reduce(user_id, old_thread, organization_id)
          Memories.flush(reduction, user_id, old_thread)
        end

        socket = do_render_flush(event, socket)

        Memories.update_memory(
          "A new thread appeared...",
          :system,
          user_id,
          socket.assigns.current_internal_thread_id
        )

        socket =
          assign(socket,
            previous_reductions:
              Bullhorn.MemoryReductions.get_last_memory_reductions_by_user_id(user_id)
          )

        {:noreply, socket}
      end

      def handle_event("view_thread", %{"thread-id" => thread_id}, socket) do
        reduction =
          Enum.find(socket.assigns.previous_reductions, &(&1.internal_thread_id == thread_id))

        messages =
          if reduction do
            [%{from: :previously, message: reduction.content}]
          else
            []
          end

        {:noreply,
         assign(socket, viewing_thread_id: thread_id, viewing_thread_messages: messages)}
      end

      def handle_event("close_thread_view", _, socket) do
        {:noreply, assign(socket, viewing_thread_id: nil, viewing_thread_messages: [])}
      end

      # Writes memory through the thread owner's OTP server so broadcasts land
      # on the owner's chat topic (which all participants are subscribed to).
      # sender_user_id identifies the actual author of each message.
      @impl true
      def handle_event("chat_to_assistant", %{"user" => %{"message" => message}}, socket) do
        current_conversation = socket.assigns.conversation
        current_user = socket.assigns.current_user
        current_internal_thread_id = socket.assigns.current_internal_thread_id
        current_organization = socket.assigns.current_organization
        thread_owner_id = socket.assigns[:thread_owner_id] || current_user.id
        staged_mentions = socket.assigns[:staged_mentions] || %{}

        # organization_ids =
        #   current_user
        #   |> Map.get(:organizations)
        #   |> Enum.map(& &1.id)

        agent_mentioned? = String.contains?(String.downcase(message), "@quip")

        mentioned_user_ids =
          staged_mentions
          |> Enum.filter(fn {handle, _id} ->
            String.contains?(String.downcase(message), "@" <> handle)
          end)
          |> Enum.map(fn {_handle, id} -> id end)
          |> Enum.reject(&(&1 == current_user.id))

        # Only the thread owner creates invitations. Guests can @-mention people but
        # those won't pull anyone new into the thread until the owner approves.
        if thread_owner_id == current_user.id do
          existing_participants =
            Bullhorn.ThreadInvitations.participants_for_thread(current_internal_thread_id)

          new_invitee_ids =
            mentioned_user_ids
            |> Enum.reject(&(&1 in existing_participants))

          for invitee_id <- new_invitee_ids do
            {:ok, invitation} =
              Bullhorn.ThreadInvitations.invite(%{
                internal_thread_id: current_internal_thread_id,
                invited_user_id: invitee_id,
                invited_by_user_id: current_user.id,
                organization_id: current_organization.id,
                status: "pending"
              })

            Phoenix.PubSub.broadcast(
              Bullhorn.PubSub,
              "user:#{invitee_id}:invitations",
              {:invitation_received, invitation.id}
            )
          end
        end

        agent_auto? =
          Bullhorn.ThreadInvitations.agent_should_auto_respond?(current_internal_thread_id)

        agent_should_run? = agent_auto? or agent_mentioned?

        updated_conversation =
          Enum.concat(current_conversation, [
            %{message: message, from: :user, sender_user_id: current_user.id}
          ])

        Memories.update_memory(
          message,
          :user,
          thread_owner_id,
          current_internal_thread_id,
          mentioned_user_ids,
          current_user.id
        )

        socket =
          if agent_should_run? do
            event =
              socket.assigns.assistant_event
              |> AssemblyLine.update_assigns(
                Map.merge(
                  %{
                    previous_messages: socket.assigns.full_conversation_context,
                    latest_message: message,
                    current_user_id: current_user.id,
                    thread_owner_id: thread_owner_id,
                    organization_id: current_organization.id,
                    current_internal_thread_id: current_internal_thread_id,
                    mentioned_user_ids: mentioned_user_ids,
                    researched_arguments: %{
                      organization_ids: [current_organization.id],
                      current_user_id: current_user.id
                    }
                  },
                  article_context_assigns(socket.assigns)
                )
              )

            socket
            |> assign(agent_thinking: true)
            |> start_async(:process_conversation, fn ->
              Bullhorn.AIPipeline.Assistant.execute(event)
            end)
          else
            socket
          end

        {:noreply,
         assign(socket,
           conversation: updated_conversation,
           msg_value: "",
           mention_results: [],
           staged_mentions: %{}
         )}
      end

      def handle_event("mention_added", %{"user_id" => user_id, "handle" => handle}, socket) do
        staged = socket.assigns[:staged_mentions] || %{}
        {:noreply, assign(socket, staged_mentions: Map.put(staged, handle, user_id))}
      end

      def handle_info({:invitation_received, invitation_id}, socket) do
        invitation =
          Bullhorn.Repo.get(Bullhorn.ThreadInvitations.ThreadInvitation, invitation_id)
          |> Bullhorn.Repo.preload(:invited_by_user)

        existing = socket.assigns[:chat_pending_invitations] || []
        {:noreply, assign(socket, chat_pending_invitations: [invitation | existing])}
      end

      def handle_event("accept_invitation", %{"invitation-id" => invitation_id}, socket) do
        user_id = socket.assigns.current_user.id

        case Bullhorn.ThreadInvitations.accept(invitation_id, user_id) do
          {:ok, invitation} ->
            owner_id = invitation.invited_by_user_id
            thread_id = invitation.internal_thread_id
            handle = Bullhorn.Accounts.handle_for(socket.assigns.current_user)

            # Persist the system line once (single writer) so it survives any
            # re-fetch. Live viewers pick it up via the broadcast-driven
            # re-fetch in {:participant_joined, ...}.
            Memories.update_memory(
              "@#{handle} joined the chat",
              :system,
              owner_id,
              thread_id
            )

            Phoenix.PubSub.broadcast(
              Bullhorn.PubSub,
              "chat:#{owner_id}:#{thread_id}",
              {:participant_joined, user_id, handle}
            )

            remaining =
              (socket.assigns[:chat_pending_invitations] || [])
              |> Enum.reject(&(&1.id == invitation.id))

            shared_threads = Bullhorn.ThreadInvitations.threads_user_belongs_to(user_id)

            socket =
              assign(socket,
                chat_pending_invitations: remaining,
                shared_threads: shared_threads
              )

            # Switch the accepter into the thread immediately (no refresh).
            # switch_to handles unsubscribe-old / subscribe-new + all assigns,
            # and re-fetches the conversation (now including the join line).
            switch_to(socket, thread_id, owner_id, true)

          _ ->
            {:noreply, socket}
        end
      end

      def handle_event("decline_invitation", %{"invitation-id" => invitation_id}, socket) do
        user_id = socket.assigns.current_user.id
        {:ok, _} = Bullhorn.ThreadInvitations.decline(invitation_id, user_id)

        remaining =
          (socket.assigns[:chat_pending_invitations] || [])
          |> Enum.reject(&(&1.id == invitation_id))

        {:noreply, assign(socket, chat_pending_invitations: remaining)}
      end

      def handle_event("leave_thread", _, socket) do
        user_id = socket.assigns.current_user.id
        thread_id = socket.assigns.current_internal_thread_id
        owner_id = socket.assigns[:thread_owner_id] || user_id
        handle = Bullhorn.Accounts.handle_for(socket.assigns.current_user)

        {:ok, _} = Bullhorn.ThreadInvitations.leave(thread_id, user_id)

        Memories.update_memory(
          "@#{handle} left the chat",
          :system,
          owner_id,
          thread_id
        )

        Phoenix.PubSub.broadcast(
          Bullhorn.PubSub,
          "chat:#{owner_id}:#{thread_id}",
          {:participant_left, user_id, handle}
        )

        {:noreply, socket}
      end

      def handle_event("platform_or_page_question", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent("I have a question about OneBlog", assigns)

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      def handle_event("search_for_content", _, socket) do
        assigns = socket.assigns

        %{event: event, updated_conversation: updated_conversation} =
          Memories.UserActionHelpers.chat_to_agent(
            "Can you help me search my blogs, articles and organizations?",
            assigns
          )

        socket =
          socket
          |> assign(agent_thinking: true)
          |> start_async(:process_conversation, fn ->
            Bullhorn.AIPipeline.Assistant.execute(event)
          end)

        {:noreply, assign(socket, conversation: updated_conversation)}
      end

      @impl true
      def handle_async(:process_conversation, {:ok, event}, socket) do
        current_user = socket.assigns.current_user
        thread_owner_id = socket.assigns[:thread_owner_id] || current_user.id
        thread_id = socket.assigns.current_internal_thread_id
        organization = socket.assigns.current_organization

        assistant_reply =
          event.assigns[:assistant_reply] || (event.response && event.response.content)

        redirect_url = event.assigns[:redirect_url]

        updated_conversation =
          Enum.concat(socket.assigns.conversation, [
            %{message: assistant_reply, from: :assistant, sender_user_id: nil}
          ])

        if assistant_reply do
          Memories.reconcile_new_memory(
            assistant_reply,
            :assistant,
            thread_owner_id,
            thread_id,
            organization.id,
            [],
            nil
          )
        end

        socket =
          socket
          |> assign(
            conversation: updated_conversation,
            assistant_event: event,
            agent_thinking: event.assigns[:batch_in_flight] == true
          )

        socket =
          if redirect_url do
            push_navigate(socket, to: redirect_url)
          else
            socket
          end

        {:noreply, socket}
      end

      def handle_async(:process_conversation, {:exit, reason}, socket) do
        require Logger
        Logger.error("Assistant pipeline crashed: #{inspect(reason)}")

        socket =
          socket
          |> assign(agent_thinking: false)
          |> put_flash(:error, "Something went wrong processing your message.")

        {:noreply, socket}
      end

      @impl true
      def handle_async(:no_opp, {_, _event}, socket) do
        {:noreply, socket}
      end

      @impl true
      def handle_async(:return_conversate, {_, _event}, socket) do
        {:noreply, socket}
      end

      defp do_render_flush(event, socket) do
        assigns = if is_map(event) and Map.has_key?(event, :assigns), do: event.assigns, else: %{}

        new_event =
          socket.view.assistant_event()
          |> AssemblyLine.update_assigns(assigns)

        new_internal_thread_id = AssemblyLine.get_internal_thread(new_event)

        socket
        |> assign(
          conversation: [],
          current_internal_thread_id: new_internal_thread_id,
          assistant_event: new_event,
          full_conversation_context: []
        )
      end

      # When the current LV is the article editor (has @article assigned), include
      # article_id + article_content on the event so the planner can switch into
      # scatter mode for image generation.
      defp article_context_assigns(%{article: %{id: article_id}} = assigns) do
        %{
          article_id: article_id,
          article_content: assigns[:content] || ""
        }
      end

      defp article_context_assigns(_), do: %{}
    end
  end

  defmacro __before_compile__(env) do
    actions =
      case Module.get_attribute(env.module, :actions) do
        nil ->
          [
            "conversate",
            "create_basic_article",
            "create_basic_article_batch",
            "generate_images",
            "change_to_different_page",
            "platform_or_page_question",
            "search_for_content"
          ]

        list ->
          list
      end

    quote do
      def actions, do: unquote(actions)
    end
  end
end

Bullhorn.IntentRouter.route_guide([
  "conversate",
  "create_basic_article",
  "create_basic_article_batch",
  "generate_images",
  "change_to_different_page",
  "platform_or_page_question",
  "search_for_content"
])
