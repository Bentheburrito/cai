defmodule CAI.Character.GameSession do
  @moduledoc """
  A Projector for a particular character's PS2 session. A projection of this
  kind will be keyed by {character_id, start_ts}, where start_ts is the value
  of the `timestamp` field in the first event (most of the time, a
  `PlayerLogin` event) that denotes the beginning of this session.
  """
  import CAI.XP

  alias CAI.Event.ContinentLock
  alias CAI.Event.ContinentUnlock
  alias CAI.Event.Death
  alias CAI.Event.FacilityControl
  alias CAI.Event.GainExperience
  alias CAI.Event.MetagameEvent
  alias CAI.Event.PlayerFacilityCapture
  alias CAI.Event.PlayerFacilityDefend
  alias CAI.Event.PlayerLogout
  alias CAI.Event.VehicleDestroy

  @derive JSON.Encoder
  @enforce_keys ~w|character_id began_at|a
  defstruct character_id: nil,
            world_id: nil,
            status: :in_progress,
            began_at: nil,
            ended_at: nil,
            kill_count: 0,
            kill_hs_count: 0,
            kill_hs_ivi_count: 0,
            kill_ivi_count: 0,
            kill_map: %{},
            death_ivi_count: 0,
            death_count: 0,
            death_map: %{},
            revive_count: 0,
            revived_by_count: 0,
            vehicle_kill_count: 0,
            vehicle_death_count: 0,
            nanites_destroyed: 0,
            nanites_lost: 0,
            xp_earned: 0,
            timeline: []

  def init(character_id, %{timestamp: began_at} = event) do
    %__MODULE__{
      character_id: character_id,
      world_id: Map.get(event, :world_id),
      began_at: began_at,
      ended_at: began_at,
      timeline: [entry(event)]
    }
  end

  defguardp has_my_character_id(event, character_id)
            when :erlang.map_get(:character_id, event) == character_id or
                   :erlang.map_get(:other_id, event) == character_id or
                   :erlang.map_get(:attacker_character_id, event) == character_id

  def handle_event(%__MODULE__{status: status} = state, _event) when status in [:logged_out, :timed_out], do: state

  @world_level_events [ContinentUnlock, ContinentLock, FacilityControl, MetagameEvent]
  def handle_event(%__MODULE__{} = state, %mod{} = event)
      when mod not in @world_level_events and not has_my_character_id(event, state.character_id),
      do: state

  @timeout_seconds div(:timer.minutes(20), 1000)
  def handle_event(%__MODULE__{} = state, %mod{} = event) do
    if event.timestamp - @timeout_seconds > state.ended_at do
      struct!(state, status: :timed_out)
    else
      status = if mod == PlayerLogout, do: :logged_out, else: :in_progress

      state
      |> update_aggregates(event)
      |> put_new_world_id(event)
      |> struct!(
        timeline: add_event_to_timeline(state.timeline, event),
        ended_at: event.timestamp,
        status: status
      )
    end
  end

  defp put_new_world_id(%__MODULE__{world_id: nil} = state, event),
    do: struct!(state, world_id: Map.get(event, :world_id))

  defp put_new_world_id(%__MODULE__{} = state, _event), do: state

  @addl_event_condensing_window_seconds 1
  @condensable_events [Death, VehicleDestroy, PlayerFacilityCapture, PlayerFacilityDefend]
  defp add_event_to_timeline(timeline, %mod{} = event) when mod in @condensable_events do
    {entries_to_search, timeline} =
      Enum.split_while(timeline, &(&1.event.timestamp > event.timestamp - @addl_event_condensing_window_seconds))

    {addl_entries, to_put_back_in_timeline} = Enum.split_with(entries_to_search, &addl_event?(event, &1.event))

    [entry(event, Enum.map(addl_entries, & &1.event)) | to_put_back_in_timeline ++ timeline]
  end

  defp add_event_to_timeline(timeline, %{experience_id: id} = event) when is_kill_xp(id) or is_vehicle_bonus_xp(id) do
    add_addl_event(timeline, event)
  end

  defp add_event_to_timeline(timeline, %FacilityControl{} = event) do
    add_addl_event(timeline, event)
  end

  defp add_event_to_timeline([prev_entry | timeline], event) do
    if consecutive?(prev_entry.event, event) do
      [update_in(prev_entry.count, &(&1 + 1)) | timeline]
    else
      [entry(event) | timeline]
    end
  end

  defp add_event_to_timeline(timeline, event) do
    [entry(event) | timeline]
  end

  defp addl_event?(%Death{} = event, %GainExperience{} = maybe_addl) when is_kill_xp(maybe_addl.experience_id) do
    event.timestamp == maybe_addl.timestamp and event.attacker_character_id == maybe_addl.character_id and
      event.character_id == maybe_addl.other_id
  end

  defp addl_event?(%VehicleDestroy{} = event, %GainExperience{} = maybe_addl)
       when is_vehicle_bonus_xp(maybe_addl.experience_id) do
    event.timestamp == maybe_addl.timestamp and event.attacker_character_id == maybe_addl.character_id
  end

  defp addl_event?(%mod{} = event, %FacilityControl{} = maybe_addl)
       when mod in [PlayerFacilityCapture, PlayerFacilityDefend] do
    event.timestamp == maybe_addl.timestamp and event.world_id == maybe_addl.world_id and
      event.zone_id == maybe_addl.zone_id and event.facility_id == maybe_addl.facility_id
  end

  defp addl_event?(_event, _other_event), do: false

  defp add_addl_event(timeline, event) do
    {entries_to_search, timeline} =
      Enum.split_while(timeline, &(&1.event.timestamp > event.timestamp - @addl_event_condensing_window_seconds))

    {updated_events, changed?} =
      Enum.map_reduce(entries_to_search, false, fn candidate_entry, changed? ->
        if addl_event?(candidate_entry.event, event) do
          {update_in(candidate_entry.addl_events, &[event | &1]), true}
        else
          {candidate_entry, changed?}
        end
      end)

    if changed?, do: updated_events ++ timeline, else: [entry(event) | updated_events ++ timeline]
  end

  defp entry(event, addl_events \\ []), do: %{count: 1, event: event, addl_events: addl_events}

  @keys ~w|character_id character_loadout_id attacker_character_id attacker_loadout_id attacker_weapon_id other_id experience_id|a
  defp consecutive?(%mod1{} = e1, %mod2{} = e2) do
    mod1 == mod2 and Map.take(e1, @keys) == Map.take(e2, @keys)
  end

  ### aggregates stuff ###

  defp update_aggregates(%__MODULE__{} = state, %GainExperience{} = ge) when is_revive_xp(ge.experience_id) do
    revive_add = if ge.character_id == state.character_id, do: 1, else: 0
    revived_by_add = if ge.other_id == state.character_id, do: 1, else: 0

    struct!(state,
      revive_count: state.revive_count + revive_add,
      revived_by_count: state.revive_count + revived_by_add,
      xp_earned: state.xp_earned + ge.amount
    )
  end

  defp update_aggregates(%__MODULE__{character_id: id} = state, %Death{character_id: id} = death) do
    death_ivi_add = if CAI.get_weapon(death.attacker_weapon_id)["sanction"] == "infantry", do: 1, else: 0

    struct!(state,
      death_count: state.death_count + 1,
      death_ivi_count: state.death_ivi_count + death_ivi_add,
      death_map: Map.update(state.death_map, death.attacker_character_id, 1, &(&1 + 1))
    )
  end

  defp update_aggregates(%__MODULE__{character_id: id} = state, %Death{attacker_character_id: id} = death) do
    kill_ivi_add = if CAI.get_weapon(death.attacker_weapon_id)["sanction"] == "infantry", do: 1, else: 0
    kill_hs_add = if death.is_headshot, do: 1, else: 0
    kill_hs_ivi_add = if kill_ivi_add == 1 and kill_hs_add == 1, do: 1, else: 0

    struct!(state,
      kill_count: state.kill_count + 1,
      kill_ivi_count: state.kill_ivi_count + kill_ivi_add,
      kill_hs_count: state.kill_hs_count + kill_hs_add,
      kill_hs_ivi_count: state.kill_hs_ivi_count + kill_hs_ivi_add,
      kill_map: Map.update(state.kill_map, death.character_id, 1, &(&1 + 1))
    )
  end

  defp update_aggregates(%__MODULE__{character_id: id} = state, %VehicleDestroy{character_id: id} = vd) do
    struct!(state,
      vehicle_death_count: state.vehicle_death_count + 1,
      nanites_lost: state.nanites_lost + (CAI.get_vehicle(vd.vehicle_id)["cost"] || 0)
    )
  end

  defp update_aggregates(%__MODULE__{character_id: id} = state, %VehicleDestroy{attacker_character_id: id} = vd) do
    struct!(state,
      vehicle_kill_count: state.vehicle_kill_count + 1,
      nanites_destroyed: state.nanites_destroyed + (CAI.get_vehicle(vd.vehicle_id)["cost"] || 0)
    )
  end

  defp update_aggregates(%__MODULE__{} = state, _event), do: state

  def load(attrs) do
    struct(
      __MODULE__,
      Stream.map(attrs, fn
        {"status", status_str} -> {:status, String.to_existing_atom(status_str)}
        {"timeline", entry_attrs_list} -> {:timeline, Enum.map(entry_attrs_list, &load_entry/1)}
        {k, v} -> {String.to_existing_atom(k), v}
      end)
    )
  end

  defp load_entry(entry_attrs) do
    %{
      count: entry_attrs["count"],
      event: cast_event!(entry_attrs["event"]),
      addl_events: Enum.map(entry_attrs["addl_events"], &cast_event!/1)
    }
  end

  defp cast_event!(event_attrs) do
    {:ok, event} = CAI.Event.Type.cast(event_attrs)
    event
  end
end
