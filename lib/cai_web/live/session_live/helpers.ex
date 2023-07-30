defmodule CAIWeb.SessionLive.Helpers do
  @moduledoc """
  Helper functions for SessionLive
  """
  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router,
    statics: CAIWeb.static_paths()

  import CAI.Guards, only: [is_kill_xp: 1]
  import Phoenix.{Component, LiveView}

  alias CAI.ESS.{
    Death,
    FacilityControl,
    GainExperience,
    Helpers,
    MetagameEvent,
    PlayerFacilityCapture,
    PlayerFacilityDefend
  }

  alias CAI.Characters
  alias CAIWeb.SessionLive.Entry

  require Logger

  @prepend 0
  @append -1
  @events_limit 15
  @time_update_interval 3000

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
  def get_session_history(session, login, logout, socket) do
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

  def event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end

  defp group_key(%Death{} = death), do: {death.timestamp, death.attacker_character_id, death.character_id}
  defp group_key(%GainExperience{} = ge), do: {ge.timestamp, ge.character_id, ge.other_id}
  defp group_key(%PlayerFacilityCapture{} = cap), do: {cap.timestamp, cap.world_id, cap.zone_id, cap.facility_id}
  defp group_key(%PlayerFacilityDefend{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}
  defp group_key(%FacilityControl{} = def), do: {def.timestamp, def.world_id, def.zone_id, def.facility_id}
end