defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAIWeb.EventFeed
  import CAIWeb.SessionComponents
  import CAIWeb.Utils
  import CAIWeb.SessionLive.Helpers
  import Phoenix.Component, only: [assign: 2]

  alias CAI.Event.PlayerLogout

  alias CAI.Character.GameSession
  alias CAI.Character.GameSessionList
  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAIWeb.SessionLive.Blurbs
  alias CAIWeb.SessionLive.Show.Model
  alias CAI.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15
  @time_update_interval :timer.seconds(1) + 100

  ### MOUNT AND HANDLE_PARAMS ###

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> Model.assign_new(0, 0)
      |> stream_configure(:events, dom_id: &CAIWeb.SessionLive.Helpers.event_to_dom_id/1)
    }
  end

  # Historical Session
  @impl true
  def handle_params(%{"character_id" => character_id, "login" => login, "logout" => logout}, _, socket) do
    with {:ok, login} <- parse_int_param(login, socket),
         {:ok, logout} <- parse_int_param(logout, socket),
         {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, %GameSession{} = session} <- get_session_history(character.character_id, login, socket) do
      {init_entries, remaining_entries} = Enum.split(session.timeline, @events_limit)

      bulk_append(init_entries, character, length(init_entries))

      {
        :noreply,
        socket
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> assign(page_title: "#{character.name_first}'s Previous Session")
        |> Model.put(
          session: session,
          character: character,
          duration_mins: Float.round((logout - login) / 60, 2),
          live?: false,
          loading_more?: true,
          remaining_events: remaining_entries,
          login: login,
          logout: logout
        )
        |> refresh_aggregate_characters()
      }
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         # {:ok, _c, timestamps} <- Characters.get_session_boundaries(character.character_id, 1) do
         {:ok, %GameSession{} = session} <- get_current_session(character, socket) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns.model.character do
          PubSub.unsubscribe(PubSub.character_event(socket.assigns.model.character.character_id))
        end

        PubSub.subscribe(PubSub.character_event(character.character_id))

        if is_integer(session.world_id), do: PubSub.subscribe(PubSub.world_event(session.world_id))
      end

      Process.send_after(self(), :time_update, @time_update_interval)

      {init_entries, remaining_entries} = Enum.split(session.timeline, @events_limit)

      bulk_append(init_entries, character, length(init_entries))

      {
        :noreply,
        socket
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> Model.put(
          remaining_events: remaining_entries,
          # aggregates: aggregates,
          session: session,
          character: character,
          live?: true,
          page_title: "#{character.name_first}'s Session",
          pending_groups: %{},
          login: session.began_at,
          logout: System.os_time(:second)
        )
        |> refresh_aggregate_characters()
      }
    end
  end

  defp get_current_session(character, socket) do
    %GameSessionList{} = session_list = CAI.game_sessions(character.character_id)
    online? = Characters.online?(character.character_id)

    case session_list.sessions do
      [%GameSession{status: :in_progress} = session | _] when online? ->
        {:ok, session}

      _else ->
        {:noreply,
         socket
         |> put_flash(:info, "#{character.name_first} is not online.")
         |> push_navigate(to: ~p"/sessions/#{character.character_id}")}
    end
  end

  ### HANDLE EVENTS AND MESSAGES ###

  # Make "Load More" button presses synchronous
  def handle_event("load-more-events", _params, %{assigns: %{model: %Model{loading_more?: true}}} = socket) do
    {:noreply, socket}
  end

  # Stream some more events (if there are any) when "Load More" is clicked
  @impl true
  def handle_event("load-more-events", _params, socket) do
    case split_events_while(socket.assigns.model.remaining_events, @events_limit) do
      {[], _, _} ->
        {:noreply, Model.put(socket, :remaining_events, [])}

      {events_to_stream, remaining_events, events_limit} ->
        new_events_limit = socket.assigns.model.events_limit + events_limit
        bulk_append(events_to_stream, socket.assigns.model.character, new_events_limit)

        {:noreply,
         socket |> Model.put(remaining_events: remaining_events, loading_more?: true) |> refresh_aggregate_characters()}
    end
  end

  def handle_event("toggle-blurbs", _params, socket) do
    voicepack = List.first(Blurbs.voicepacks())

    {
      :noreply,
      socket
      |> Model.update(:blurbs, fn
        :disabled -> {:enabled, %Blurbs{voicepack: voicepack}}
        _ -> :disabled
      end)
      |> push_login_blurb()
    }
  end

  def handle_event("blurb-ended", _params, socket) do
    with {:enabled, %Blurbs{} = blurbs} <- socket.assigns.model.blurbs,
         [next_category | rest] <- blurbs.track_queue,
         {:ok, track_filename} <- Blurbs.get_random_blurb_filename(next_category, blurbs) do
      {
        :noreply,
        socket
        |> push_event("play-blurb", %{"track" => track_filename})
        |> Model.put(:blurbs, {:enabled, %Blurbs{blurbs | playing?: true, track_queue: rest}})
      }
    else
      _ ->
        {:noreply,
         Model.update(socket, :blurbs, fn
           {:enabled, %Blurbs{} = blurbs} -> {:enabled, %Blurbs{blurbs | playing?: false}}
           :disabled -> :disabled
         end)}
    end
  end

  def handle_event("voicepack-selected", %{"voicepack-select" => voicepack}, socket) do
    {
      :noreply,
      socket
      |> Model.update(:blurbs, fn
        {:enabled, %Blurbs{} = blurbs} ->
          {:enabled, %Blurbs{blurbs | voicepack: voicepack}}

        :disabled ->
          :disabled
      end)
      |> push_login_blurb()
    }
  end

  def handle_event("blurb-vol-change", %{"blurb-volume" => value}, socket) do
    value = String.to_integer(value)

    {
      :noreply,
      socket
      |> push_event("change-blurb-volume", %{"value" => value})
      |> Model.update(:blurbs, fn
        {:enabled, %Blurbs{} = blurbs} ->
          {:enabled, %Blurbs{blurbs | volume: value}}

        :disabled ->
          :disabled
      end)
    }
  end

  # Historic Session - bulk insert the given event tuples
  @impl true
  def handle_info({:bulk_append, entries, new_events_limit}, socket) do
    {
      :noreply,
      socket
      |> stream(:events, entries, at: @append, limit: new_events_limit)
      |> Model.put(events_limit: new_events_limit, loading_more?: false, last_entry: List.first(entries))
    }
  end

  # Live Session - receive a new event via PubSub
  @impl true
  def handle_info({msg_type, event}, socket) when msg_type in [:event_handled, :apply_event] do
    %Model{session: session, logout: logout} = socket.assigns.model

    %GameSession{timeline: [entry | _]} = session = GameSession.handle_event(session, event.struct)

    # TODO: remove - we can just redirect to the closed session page when they go offline
    logout = if match?(%PlayerLogout{}, event), do: :offline, else: logout

    socket = Model.put(socket, session: session, logout: logout)
    socket = Blurbs.maybe_push_blurb(event.struct, socket)

    socket
    |> refresh_aggregate_characters()
    |> handle_ess_event(entry)
  end

  # Live Session - we've waited long enough to receive a primary event and any bonuses, so combine them into an Entry.
  @impl true
  def handle_info({:build_entries_from_group, pending_key}, socket) do
    case Map.fetch(socket.assigns.model.pending_groups, pending_key) do
      {:ok, group} ->
        build_entries_from_group(pending_key, group, socket)

      :error ->
        Logger.error("Received :build_entries_from_group message, but no group was found under #{inspect(pending_key)}")
        {:noreply, socket}
    end
  end

  # Live Session - Update the `logout` time every few seconds, unless the character is no longer online.
  @impl true
  def handle_info(:time_update, socket) do
    if Characters.online?(socket.assigns.model.character.character_id) do
      login = socket.assigns.model.login
      logout = System.os_time(:second)

      duration_mins = Float.round((logout - login) / 60, 2)

      Process.send_after(self(), :time_update, @time_update_interval)
      {:noreply, Model.put(socket, login: login, logout: logout, duration_mins: duration_mins)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:fetch, query, result}, socket) do
    {to_update, new_pending_queries} = Map.pop(socket.assigns.model.pending_queries, query, [])
    socket = Model.put(socket, :pending_queries, new_pending_queries)

    update_char_fn =
      case result do
        {:ok, character} -> fn _c -> character end
        _ -> fn old_pc -> put_in(old_pc.state, :unavailable) end
      end

    {:noreply,
     Enum.reduce(to_update, socket, fn item, socket ->
       case item do
         {:entry, entries} -> update_entries(entries, update_char_fn, socket)
         {:aggregate, aggregate} -> update_aggregate(aggregate, update_char_fn, socket)
       end
     end)}
  end
end
