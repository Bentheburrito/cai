defmodule CAIWeb.SessionLive.Show do
  alias CAI.ESS.FacilityControl
  alias CAI.ESS.PlayerFacilityCapture
  alias CAI.ESS.PlayerFacilityDefend
  use CAIWeb, :live_view

  import CAI, only: [is_kill_xp: 1]
  import CAIWeb.ESSComponents
  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{Death, GainExperience, Helpers, MetagameEvent}
  alias CAIWeb.SessionLive.Entry
  alias Phoenix.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15

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
         {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
      {init_events, remaining_events, new_limit} = split_events_while(event_history, @events_limit)

      bulk_append(init_events, character, new_limit)

      {
        :noreply,
        socket
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> assign(:remaining_events, remaining_events)
        |> assign(:page_title, "#{character.name_first}'s Previous Session")
        |> assign(:timestamps, {login, logout})
        |> assign(:character, character)
        |> assign(:live?, false)
        |> assign(:loading_more?, true)
      }
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns[:character] do
          PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.character.character_id}")
        end

        PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
        PubSub.subscribe(CAI.PubSub, "ess:FacilityControl")
      end

      {
        :noreply,
        socket
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> assign(:page_title, "#{character.name_first}'s Session")
        |> assign(:live?, true)
        |> assign(:pending_groups, %{})
        |> assign(:character, character)
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
      entries = Entry.map(events_to_stream, character)
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

  # Live Session - receive a new Death or PlayerFacilityCapture/Defend event via PubSub
  @enrichable_events [Death, PlayerFacilityCapture, PlayerFacilityDefend]
  @event_pending_delay 1000
  @impl true
  def handle_info({:event, %Ecto.Changeset{data: %mod{}} = event_cs}, socket) when mod in @enrichable_events do
    handle_enrichable_event(event_cs, socket)
  end

  # Live Session - receive a new kill bonus GE event via PubSub
  @impl true
  def handle_info({:event, %Ecto.Changeset{changes: %{experience_id: id}} = event_cs}, socket) when is_kill_xp(id) do
    handle_bonus_event(event_cs, socket)
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{data: %FacilityControl{}} = event_cs}, socket) do
    handle_bonus_event(event_cs, socket)
  end

  # Live Session - receive a new event via PubSub
  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    character = socket.assigns.character

    other = Helpers.get_other_character(character.character_id, event)

    prev_entry = Map.get(socket.assigns, :last_entry, Entry.new(%MetagameEvent{}, %{}))

    if Helpers.consecutive?(event, prev_entry.event) do
      updated_entry = %Entry{prev_entry | count: prev_entry.count + 1}

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

  @impl true
  def handle_info({:build_entries, pending_key}, socket) do
    case Map.fetch(socket.assigns.pending_groups, pending_key) do
      {:ok, group} ->
        character = socket.assigns.character

        other_map =
          with [%{character_id: _} | _] <- group.bonuses,
               {_, char_id, other_id} = pending_key,
               placeholder_event = %GainExperience{character_id: char_id, other_id: other_id},
               %Character{} = other <- Helpers.get_other_character(character.character_id, placeholder_event) do
            %{other.character_id => other}
          else
            {:unavailable, other_id} -> %{other_id => {:unavailable, other_id}}
            _ -> %{}
          end

        entries = Entry.from_groups(%{pending_key => group}, [], character, other_map)

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

  ### HELPERS ###

  defp handle_enrichable_event(event_cs, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    pending_key = pending_key(event)

    pending_groups = socket.assigns.pending_groups

    if is_map_key(pending_groups, pending_key) do
      {:noreply, update(socket, :pending_groups, &put_in(&1, [pending_key, :death], event))}
    else
      Process.send_after(self(), {:build_entries, pending_key}, @event_pending_delay)
      {:noreply, update(socket, :pending_groups, &Map.put(&1, pending_key, %{death: event, bonuses: []}))}
    end
  end

  defp handle_bonus_event(event_cs, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    pending_key = pending_key(event)

    pending_groups = socket.assigns.pending_groups

    if is_map_key(pending_groups, pending_key) do
      updater = fn groups -> update_in(groups, [pending_key, :bonuses], &[event | &1]) end
      {:noreply, update(socket, :pending_groups, updater)}
    else
      Process.send_after(self(), {:build_entries, pending_key}, @event_pending_delay)
      {:noreply, update(socket, :pending_groups, &Map.put(&1, pending_key, %{death: nil, bonuses: [event]}))}
    end
  end

  defp pending_key(%Death{} = death), do: {death.timestamp, death.attacker_character_id, death.character_id}
  defp pending_key(%GainExperience{} = ge), do: {ge.timestamp, ge.character_id, ge.other_id}
  defp pending_key(%PlayerFacilityCapture{} = cap), do: {cap.timestamp, cap.world_id, cap.zone_id, cap.facility_id}
  defp pending_key(%PlayerFacilityDefend{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}
  defp pending_key(%FacilityControl{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}

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
  defp get_session_history(character_id, login, logout, socket) do
    case Characters.get_session_history(character_id, login, logout) do
      events when is_list(events) ->
        {:ok, events}

      {:error, changeset} ->
        Logger.error(
          "Unable to get session history because of a changeset error building the session: #{inspect(changeset)}"
        )

        {:noreply,
         socket
         |> put_flash(:error, "Unable to load that session right now. Please try again")
         |> push_navigate(to: ~p"/sessions/#{character_id}")}
    end
  end

  defp event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
