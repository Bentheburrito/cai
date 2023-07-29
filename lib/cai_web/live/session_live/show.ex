defmodule CAIWeb.SessionLive.Show do
  alias CAI.ESS.FacilityControl
  alias CAI.ESS.PlayerFacilityCapture
  alias CAI.ESS.PlayerFacilityDefend
  use CAIWeb, :live_view

  import CAI.Guards, only: [is_kill_xp: 1]
  import CAIWeb.ESSComponents
  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.Characters.Session
  alias CAI.ESS.{Death, GainExperience, Helpers, MetagameEvent}
  alias CAIWeb.SessionLive.Entry
  alias Phoenix.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15
  @time_update_interval 3000

  ### MOUNT AND HANDLE_PARAMS ###

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:live?, false)
      |> assign(:loading_more?, false)
      |> stream_configure(:events, dom_id: &event_to_dom_id/1)
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
        |> assign(:aggregates, Map.take(session, Session.aggregate_fields()))
        |> assign(:character, character)
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> assign(:live?, false)
        |> assign(:loading_more?, true)
        |> assign(:page_title, "#{character.name_first}'s Previous Session")
        |> assign(:remaining_events, remaining_events)
        |> assign(:timestamps, {login, logout})
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
        if socket.assigns[:character] do
          PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.character.character_id}")
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

      timestamps =
        case {online?, timestamps} do
          {true, [{login, logout}]} -> {login, logout}
          _ -> {:os.system_time(:second), :offline}
        end

      Process.send_after(self(), :time_update, @time_update_interval)

      {
        :noreply,
        socket
        |> assign(:aggregates, aggregates)
        |> assign(:character, character)
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> assign(:live?, true)
        |> assign(:page_title, "#{character.name_first}'s Session")
        |> assign(:pending_groups, %{})
        |> assign(:timestamps, timestamps)
      }
    end
  end

  ### HANDLE EVENTS AND MESSAGES ###

  # Make "Load More" button presses synchronous
  def handle_event("load-more-events", _params, %{assigns: %{loading_more?: true}} = socket) do
    {:noreply, socket}
  end

  # Stream some more events (if there are any) when "Load More" is clicked
  @impl true
  def handle_event("load-more-events", _params, socket) do
    case split_events_while(socket.assigns.remaining_events, @events_limit) do
      {[], _, _} ->
        {:noreply, assign(socket, :remaining_events, [])}

      {events_to_stream, remaining_events, events_limit} ->
        new_events_limit = Map.get(socket.assigns, :events_limit, @events_limit) + events_limit
        bulk_append(events_to_stream, socket.assigns.character, new_events_limit)

        {:noreply, socket |> assign(:remaining_events, remaining_events) |> assign(:loading_more?, true)}
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
      |> assign(:events_limit, new_events_limit)
      |> assign(:loading_more?, false)
    }
  end

  # Live Session - receive a new event via PubSub
  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    %{aggregates: aggregates, character: %{character_id: character_id}} = socket.assigns

    aggregates = Session.put_aggregate_event(event, aggregates, character_id)

    socket = assign(socket, :aggregates, aggregates)

    handle_ess_event(event, socket)
  end

  # Live Session - we've waited long enough to receive a primary event and any bonuses, so combine them into an Entry.
  @impl true
  def handle_info({:build_entries, pending_key}, socket) do
    case Map.fetch(socket.assigns.pending_groups, pending_key) do
      {:ok, group} ->
        character = socket.assigns.character

        character_map =
          with [%{character_id: _} | _] <- group.bonuses,
               {_, char_id, other_id} = pending_key,
               placeholder_event = %GainExperience{character_id: char_id, other_id: other_id},
               %Character{} = other <- Helpers.get_other_character(character.character_id, placeholder_event) do
            %{other.character_id => other}
          else
            {:unavailable, other_id} -> %{other_id => {:unavailable, other_id}}
            _ -> %{}
          end
          |> Map.put(character.character_id, character)

        entries = Entry.from_groups(%{pending_key => group}, [], character_map)

        {
          :noreply,
          socket
          |> update(:pending_groups, &Map.delete(&1, pending_key))
          |> stream(:events, entries, at: @prepend, limit: @events_limit)
        }

      :error ->
        Logger.error("Received :build_entries message, but no group was found under #{inspect(pending_key)}")
        {:noreply, socket}
    end
  end

  # Live Session - Update the `logout` time every few seconds, unless the character is no longer online.
  @impl true
  def handle_info(:time_update, socket) do
    last_entry =
      Map.get_lazy(socket.assigns, :last_entry, fn ->
        case socket.assigns.timestamps do
          {_login, :offline} -> Entry.new(%MetagameEvent{timestamp: 0}, %{})
          {_login, logout} -> Entry.new(%MetagameEvent{timestamp: logout}, %{})
        end
      end)

    if Helpers.online?(last_entry.event) do
      {login, _logout} = Map.fetch!(socket.assigns, :timestamps)
      Process.send_after(self(), :time_update, @time_update_interval)
      {:noreply, assign(socket, :timestamps, {login, :os.system_time(:second)})}
    else
      {:noreply, socket}
    end
  end

  ### HELPERS ###

  # Death or PlayerFacilityCapture/Defend primary event
  @enrichable_events [Death, PlayerFacilityCapture, PlayerFacilityDefend]
  @event_pending_delay 1000
  def handle_ess_event(%mod{} = event, socket) when mod in @enrichable_events do
    handle_enrichable_event(event, socket)
  end

  # kill bonus GE event
  def handle_ess_event(%{experience_id: id} = event, socket) when is_kill_xp(id) do
    handle_bonus_event(event, socket)
  end

  # facility control bonus event
  def handle_ess_event(%FacilityControl{} = event, socket) do
    handle_bonus_event(event, socket)
  end

  # catch-all/ordinary event that doesn't need to be condensed
  def handle_ess_event(event, socket) do
    character = socket.assigns.character
    other = Helpers.get_other_character(character.character_id, event)
    last_entry = Map.get(socket.assigns, :last_entry, Entry.new(%MetagameEvent{}, %{}))

    if Helpers.consecutive?(event, last_entry.event) do
      updated_entry = %Entry{last_entry | count: last_entry.count + 1}

      {
        :noreply,
        socket
        |> stream_insert(:events, updated_entry, at: @append, limit: @events_limit)
        |> assign(:last_entry, updated_entry)
      }
    else
      entry = Entry.new(event, character, other)

      {
        :noreply,
        socket
        |> stream_insert(:events, entry, at: @prepend, limit: @events_limit)
        |> assign(:last_entry, entry)
      }
    end
  end

  defp handle_enrichable_event(event, socket) do
    pending_key = group_key(event)

    pending_groups = socket.assigns.pending_groups

    if is_map_key(pending_groups, pending_key) do
      {:noreply, update(socket, :pending_groups, &put_in(&1, [pending_key, :event], event))}
    else
      Process.send_after(self(), {:build_entries, pending_key}, @event_pending_delay)
      {:noreply, update(socket, :pending_groups, &Map.put(&1, pending_key, %{event: event, bonuses: []}))}
    end
  end

  defp handle_bonus_event(event, socket) do
    pending_key = group_key(event)

    pending_groups = socket.assigns.pending_groups

    if is_map_key(pending_groups, pending_key) do
      updater = fn groups -> update_in(groups, [pending_key, :bonuses], &[event | &1]) end
      {:noreply, update(socket, :pending_groups, updater)}
    else
      Process.send_after(self(), {:build_entries, pending_key}, @event_pending_delay)
      {:noreply, update(socket, :pending_groups, &Map.put(&1, pending_key, %{event: nil, bonuses: [event]}))}
    end
  end

  defp group_key(%Death{} = death), do: {death.timestamp, death.attacker_character_id, death.character_id}
  defp group_key(%GainExperience{} = ge), do: {ge.timestamp, ge.character_id, ge.other_id}
  defp group_key(%PlayerFacilityCapture{} = cap), do: {cap.timestamp, cap.world_id, cap.zone_id, cap.facility_id}
  defp group_key(%PlayerFacilityDefend{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}
  defp group_key(%FacilityControl{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}

  # Given a list of events, this fn tries to split at `preferred_limit`, however, it might take more if events can be
  # grouped together as a single entry.
  defp split_events_while(events, preferred_limit) do
    split_events_while(_taken = [], _remaining = events, _num_taken = 0, preferred_limit)
  end

  defp split_events_while(taken, [], num_taken, _preferred_limit) do
    {Enum.reverse(taken), [], num_taken}
  end

  defp split_events_while(
         [%{timestamp: t} | _] = taken,
         [%{timestamp: t} = next | remaining],
         num_taken,
         preferred_limit
       ) do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  defp split_events_while(taken, [next | remaining], num_taken, preferred_limit) when num_taken < preferred_limit do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  defp split_events_while(taken, remaining, num_taken, _preferred_limit) do
    {Enum.reverse(taken), remaining, num_taken}
  end

  # Get a character's events from the session defined by login..logout
  defp get_session_history(session, login, logout, socket) do
    case Characters.get_session_history(session, login, logout) do
      events when is_list(events) ->
        {:ok, events}

      {:error, changeset} ->
        Logger.error(
          "Unable to get session history because of a changeset error building the session: #{inspect(changeset)}"
        )

        {:noreply,
         socket
         |> put_flash(:error, "Unable to load that session right now. Please try again")
         |> push_navigate(to: ~p"/sessions/#{session.character_id}")}
    end
  end

  defp event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
