defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAIWeb.EventFeed
  import CAIWeb.Utils
  import CAIWeb.SessionLive.Helpers
  import Phoenix.Component, only: []

  alias CAI.ESS.{Helpers, PlayerLogout}

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.Characters.Session
  alias CAIWeb.SessionLive.{Blurbs, Entry}
  alias CAIWeb.SessionLive.Show.Model
  alias Phoenix.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15
  @time_update_interval 1500

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
         {:ok, session} <- Session.build(character.character_id, login, logout),
         {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
      {init_events, remaining_events, new_limit} = split_events_while(event_history, @events_limit)

      bulk_append(init_events, character, new_limit)

      {
        :noreply,
        socket
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> Model.put(
          aggregates: Map.take(session, Session.aggregate_fields()),
          character: character,
          live?: false,
          loading_more?: true,
          page_title: "#{character.name_first}'s Previous Session",
          remaining_events: remaining_events,
          login: login,
          logout: logout
        )
      }
    else
      {:error, changeset} ->
        bubbled_errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)

        Logger.error("Could not build session: #{inspect(bubbled_errors)}")

        {
          :noreply,
          socket
          |> put_flash(
            :error,
            "Something went wrong opening that character's session, please try again. #{CAI.please_report_msg()}"
          )
          |> push_navigate(to: ~p"/sessions/#{character_id}")
        }

      {:noreply, socket} ->
        {:noreply, socket}
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, _c, timestamps} <- Characters.get_session_boundaries(character.character_id, 1) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns.model.character do
          PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.model.character.character_id}")
        end

        PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
        PubSub.subscribe(CAI.PubSub, "ess:FacilityControl")
      end

      # If the character is currently online, let's build the session so far
      online? = Helpers.online?(character.character_id, timestamps)

      aggregates =
        with true <- online?,
             [{login, logout} | _] <- timestamps,
             {:ok, session} <- Session.build(character.character_id, login, logout),
             {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
          {init_events, _remaining_events, new_limit} = split_events_while(event_history, @events_limit)

          bulk_append(init_events, character, new_limit)

          Map.take(session, Session.aggregate_fields())
        else
          false ->
            Map.new(Session.aggregate_fields(), &{&1, 0})

          {:error, changeset} ->
            Logger.error("Could not build a session handling live session params: #{inspect(changeset)}")
            Map.new(Session.aggregate_fields(), &{&1, 0})

          [] ->
            Logger.error("""
            Tried to match `[{login, logout} | _]` from `timestamps = #{inspect(timestamps)}`, but got an empty list.
            #{character.name_first} (#{character.character_id}) was confirmed online, so there should have been at least one boundary pair:
            #{online?} = Helpers.online?(#{character.character_id}, #{inspect(timestamps)})
            """)

            Map.new(Session.aggregate_fields(), &{&1, 0})

          {:noreply, _socket} ->
            Map.new(Session.aggregate_fields(), &{&1, 0})
        end

      {login, logout} =
        case {online?, timestamps} do
          {true, [{login, logout}]} -> {login, logout}
          _ -> {:os.system_time(:second), :offline}
        end

      Process.send_after(self(), :time_update, @time_update_interval)

      {
        :noreply,
        socket
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> Model.put(
          aggregates: aggregates,
          character: character,
          live?: true,
          page_title: "#{character.name_first}'s Session",
          pending_groups: %{},
          login: login,
          logout: logout
        )
      }
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

        {:noreply, Model.put(socket, remaining_events: remaining_events, loading_more?: true)}
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

  defp push_login_blurb(socket) do
    with {:enabled, %Blurbs{} = blurbs} <- socket.assigns.model.blurbs,
         {:ok, track_filename} <- Blurbs.get_random_blurb_filename("login", blurbs) do
      push_event(socket, "play-blurb", %{"track" => track_filename})
    else
      _ -> socket
    end
  end

  defp bulk_append(events_to_stream, character, new_events_limit) do
    liveview = self()

    Task.start_link(fn ->
      entries = Entry.map(events_to_stream, [character])
      send(liveview, {:bulk_append, entries, new_events_limit})
    end)
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
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    %Model{aggregates: aggregates, character: %{character_id: character_id}, logout: logout} = socket.assigns.model

    aggregates = Session.put_aggregate_event(event, aggregates, character_id)

    logout = if match?(%PlayerLogout{}, event), do: :offline, else: logout

    socket = Model.put(socket, aggregates: aggregates, logout: logout)
    socket = Blurbs.maybe_push_blurb(event, socket)

    handle_ess_event(event, socket)
  end

  # Live Session - we've waited long enough to receive a primary event and any bonuses, so combine them into an Entry.
  @impl true
  def handle_info({:build_entries, pending_key}, socket) do
    case Map.fetch(socket.assigns.model.pending_groups, pending_key) do
      {:ok, group} ->
        build_entries(pending_key, group, socket)

      :error ->
        Logger.error("Received :build_entries message, but no group was found under #{inspect(pending_key)}")
        {:noreply, socket}
    end
  end

  # Live Session - Update the `logout` time every few seconds, unless the character is no longer online.
  @impl true
  def handle_info(:time_update, socket) do
    last_entry = socket.assigns.model.last_entry

    last_event =
      if is_nil(last_entry) do
        nil
      else
        last_entry.event
      end

    if Helpers.online?(last_event) do
      login = socket.assigns.model.login
      logout = :os.system_time(:second)

      duration_mins = if logout != :offline, do: Float.round((logout - login) / 60, 2), else: 0

      Process.send_after(self(), :time_update, @time_update_interval)
      {:noreply, Model.put(socket, login: login, logout: logout, duration_mins: duration_mins)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:fetch, query, result}, socket) do
    {entries, new_pending_queries} = Map.pop(socket.assigns.model.pending_queries, query, [])
    socket = Model.put(socket, :pending_queries, new_pending_queries)

    {new_character, character_id} =
      case result do
        {:ok, %Character{} = character} ->
          {character, character.character_id}

        _ ->
          character_id = elem(query.params["character_id"], 1)
          {{:unavailable, character_id}, character_id}
      end

    new_socket =
      for entry <- entries, reduce: socket do
        socket ->
          case entry.event do
            %{character_id: ^character_id} ->
              update_entry(socket, %Entry{entry | character: new_character})

            _ ->
              update_entry(socket, %Entry{entry | other: new_character})
          end
      end

    {:noreply, new_socket}
  end

  defp build_entries({_, _, _, _} = pending_key, group, socket) do
    character = socket.assigns.model.character

    entries = Entry.from_groups(%{pending_key => group}, [], %{character.character_id => character})

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  defp build_entries(pending_key, group, socket) do
    character = socket.assigns.model.character
    pending_queries = socket.assigns.model.pending_queries

    group_event = Map.get_lazy(group, :event, fn -> group |> Map.get(:bonuses, []) |> List.first() end)
    other = Helpers.get_other_character(character.character_id, group_event, &Characters.fetch_async/1)

    other_id =
      case other do
        %Character{character_id: id} -> id
        {_, id} -> id
        {_, id, _} -> id
        :none -> nil
      end

    character_map = %{character.character_id => character, other_id => other}
    entries = Entry.from_groups(%{pending_key => group}, [], character_map)

    pending_queries =
      Enum.reduce(character_map, pending_queries, fn
        {_, {:being_fetched, _other_id, query}}, acc -> Map.update(acc, query, entries, &(entries ++ &1))
        _, acc -> acc
      end)

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> Model.put(:pending_queries, pending_queries)
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  defp update_entry(socket, entry) do
    socket = stream_insert(socket, :events, entry, at: @append)

    if socket.assigns.model.last_entry == entry do
      Model.put(socket, :last_entry, entry)
    else
      socket
    end
  end
end
