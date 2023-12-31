defmodule CAIWeb.SessionLive.Helpers do
  @moduledoc """
  Helper functions for SessionLive
  """
  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router,
    statics: CAIWeb.static_paths()

  import CAI.Guards, only: [is_kill_xp: 1, is_vehicle_bonus_xp: 1]
  import Phoenix.LiveView

  alias CAI.Characters.Session

  alias CAI.ESS.{
    Death,
    FacilityControl,
    GainExperience,
    Helpers,
    MetagameEvent,
    PlayerFacilityCapture,
    PlayerFacilityDefend,
    VehicleDestroy
  }

  alias CAI.Characters
  alias CAIWeb.SessionLive.{Blurbs, Entry}
  alias CAIWeb.SessionLive.Show.Model

  require Logger

  @prepend 0
  @append -1
  @events_limit 15

  # Death or PlayerFacilityCapture/Defend primary event
  @enrichable_events [Death, VehicleDestroy, PlayerFacilityCapture, PlayerFacilityDefend]
  @event_pending_delay 1000
  def handle_ess_event(socket, %mod{} = event) when mod in @enrichable_events do
    handle_enrichable_event(event, socket)
  end

  # kill or vehicle bonus GE event
  def handle_ess_event(socket, %{experience_id: id} = event) when is_kill_xp(id) or is_vehicle_bonus_xp(id) do
    handle_bonus_event(event, socket)
  end

  # facility control bonus event (only for the current world)
  def handle_ess_event(socket, %FacilityControl{world_id: world_id} = event)
      when world_id == socket.assigns.model.world_id do
    handle_bonus_event(event, socket)
  end

  # ignore facility control events not for the current world
  def handle_ess_event(socket, %FacilityControl{}) do
    {:noreply, socket}
  end

  # catch-all/ordinary event that doesn't need to be condensed
  def handle_ess_event(socket, event) do
    last_entry = socket.assigns.model.last_entry || Entry.new(%MetagameEvent{timestamp: :os.system_time(:second)}, %{})

    socket =
      if is_map_key(event, :world_id) and not match?(%FacilityControl{}, event),
        do: Model.put(socket, :world_id, event.world_id),
        else: socket

    if Helpers.consecutive?(event, last_entry.event) do
      updated_entry = %Entry{last_entry | count: last_entry.count + 1}

      {
        :noreply,
        socket
        |> stream_insert(:events, updated_entry, at: @append, limit: @events_limit)
        |> Model.put(:last_entry, updated_entry)
      }
    else
      %{character_id: character_id} = character = socket.assigns.model.character

      other =
        character_id
        |> Helpers.get_other_character_id(event)
        |> Entry.async_fetch_presentable_character()

      entry =
        case event do
          %{character_id: ^character_id} -> Entry.new(event, character, other)
          _ -> Entry.new(event, other, character)
        end

      {
        :noreply,
        socket
        |> stream_insert(:events, entry, at: @prepend, limit: @events_limit)
        |> update_pending_queries(other, {:entry, entry})
        |> Model.put(:last_entry, entry)
      }
    end
  end

  defp handle_enrichable_event(event, socket) do
    pending_key = group_key(event)

    pending_groups = socket.assigns.model.pending_groups

    if is_map_key(pending_groups, pending_key) do
      {:noreply, Model.update(socket, :pending_groups, &put_in(&1, [pending_key, :event], event))}
    else
      Process.send_after(self(), {:build_entries_from_group, pending_key}, @event_pending_delay)
      {:noreply, Model.update(socket, :pending_groups, &Map.put(&1, pending_key, %{event: event, bonuses: []}))}
    end
  end

  defp handle_bonus_event(event, socket) do
    pending_key = group_key(event)

    pending_groups = socket.assigns.model.pending_groups

    if is_map_key(pending_groups, pending_key) do
      updater = fn groups -> update_in(groups, [pending_key, :bonuses], &[event | &1]) end
      {:noreply, Model.update(socket, :pending_groups, updater)}
    else
      Process.send_after(self(), {:build_entries_from_group, pending_key}, @event_pending_delay)
      {:noreply, Model.update(socket, :pending_groups, &Map.put(&1, pending_key, %{event: nil, bonuses: [event]}))}
    end
  end

  # Given a list of events, this fn tries to split at `preferred_limit`, however, it might take more if events can be
  # grouped together as a single entry.
  def split_events_while(events, preferred_limit) do
    split_events_while(_taken = [], _remaining = events, _num_taken = 0, preferred_limit)
  end

  def split_events_while(taken, [], num_taken, _preferred_limit) do
    {Enum.reverse(taken), [], num_taken}
  end

  def split_events_while(
        [%{timestamp: t} | _] = taken,
        [%{timestamp: t} = next | remaining],
        num_taken,
        preferred_limit
      ) do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  def split_events_while(taken, [next | remaining], num_taken, preferred_limit) when num_taken < preferred_limit do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  def split_events_while(taken, remaining, num_taken, _preferred_limit) do
    {Enum.reverse(taken), remaining, num_taken}
  end

  # Get a character's events from the session defined by login..logout
  def get_session_history(%Session{} = session, login, logout, _socket) do
    events = Characters.get_session_history(session, login, logout)

    {:ok, session, events}
  end

  def get_session_history(character_id, login, logout, socket) do
    case Session.build(character_id, login, logout) do
      {:ok, session} ->
        get_session_history(session, login, logout, socket)

      {:error, error} ->
        Logger.error("Could not build a session for #{character_id}: #{inspect(error)}")

        {:noreply,
         socket
         |> put_flash(:error, "Unable to load that session right now. Please try again")
         |> push_navigate(to: ~p"/sessions/#{character_id}")}
    end
  end

  def push_login_blurb(socket) do
    with {:enabled, %Blurbs{} = blurbs} <- socket.assigns.model.blurbs,
         {:ok, track_filename} <- Blurbs.get_random_blurb_filename("login", blurbs) do
      push_event(socket, "play-blurb", %{"track" => track_filename})
    else
      _ -> socket
    end
  end

  def bulk_append(events_to_stream, character, new_events_limit) do
    liveview = self()

    Task.start_link(fn ->
      other_character_ids =
        Stream.flat_map(
          events_to_stream,
          &(Map.take(&1, [:character_id, :attacker_character_id, :other_id]) |> Map.values())
        )
        |> MapSet.new()
        |> MapSet.difference(MapSet.new([nil, 0, character.character_id]))

      character_map = other_character_ids |> Characters.get_many() |> Map.put(character.character_id, character)

      entries = Entry.map(events_to_stream, character_map)
      send(liveview, {:bulk_append, entries, new_events_limit})
    end)
  end

  def update_entries(entry, update_char_fn, socket) do
    %{character_id: character_id} = socket.assigns.model.character

    new_socket =
      case entry.event do
        %{character_id: ^character_id} ->
          update_entry(socket, %Entry{entry | other: update_char_fn.(entry.other)})

        _ ->
          update_entry(socket, %Entry{entry | character: update_char_fn.(entry.character)})
      end

    new_socket
  end

  def update_aggregate(field, update_char_fn, socket) do
    Model.update(socket, :aggregates, &update_in(&1, [field, :character], update_char_fn))
  end

  def build_entries_from_group({_, _, _, _} = pending_key, group, socket) do
    character = socket.assigns.model.character
    entries = Entry.from_groups(%{pending_key => group}, [], %{character.character_id => character})

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  def build_entries_from_group(pending_key, group, socket) do
    character = socket.assigns.model.character

    group_event = Map.get_lazy(group, :event, fn -> group |> Map.get(:bonuses, []) |> List.first() end)
    other_id = Helpers.get_other_character_id(character.character_id, group_event)
    other = Entry.async_fetch_presentable_character(other_id)

    character_map = %{character.character_id => character, other_id => other}
    entries = Entry.from_groups(%{pending_key => group}, [], character_map)
    labeled_entries = Enum.map(entries, &{:entry, &1})

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> update_pending_queries(other, labeled_entries)
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  def update_entry(socket, entry) do
    if event_to_dom_id(socket.assigns.model.last_entry) == event_to_dom_id(entry) do
      Model.put(socket, :last_entry, entry)
    else
      socket
    end
    |> stream_insert(:events, entry, at: @append)
  end

  def refresh_aggregate_characters(socket) do
    Enum.reduce(Session.aggregate_character_fields(), socket, fn field, socket ->
      character = Entry.async_fetch_presentable_character(socket.assigns.model.aggregates[field].character.character_id)

      socket
      |> update_pending_queries(character, {:aggregate, field})
      |> Model.update(:aggregates, &put_in(&1, [field, :character], character))
    end)
  end

  def event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end

  defp group_key(%Death{} = death), do: {death.timestamp, death.attacker_character_id, death.character_id}
  defp group_key(%VehicleDestroy{} = vd), do: {:vehicle, vd.timestamp, vd.attacker_character_id}

  defp group_key(%GainExperience{experience_id: id} = ge) when is_vehicle_bonus_xp(id),
    do: {:vehicle, ge.timestamp, ge.character_id}

  defp group_key(%GainExperience{} = ge), do: {ge.timestamp, ge.character_id, ge.other_id}
  defp group_key(%PlayerFacilityCapture{} = cap), do: {cap.timestamp, cap.world_id, cap.zone_id, cap.facility_id}
  defp group_key(%PlayerFacilityDefend{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}
  defp group_key(%FacilityControl{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}

  defp update_pending_queries(socket, character, item_to_update) when not is_list(item_to_update),
    do: update_pending_queries(socket, character, [item_to_update])

  defp update_pending_queries(socket, character, items_to_update) do
    case character do
      %{state: {:loading, query}} ->
        Model.update(
          socket,
          :pending_queries,
          &Map.update(&1, query, items_to_update, fn items -> items_to_update ++ items end)
        )

      _ ->
        socket
    end
  end
end
