defmodule CAIWeb.SessionLive.Entry do
  @moduledoc """
  This module/struct represents a single line/message/entry in the Event Feed. It contains the ESS event struct that
  makes up the entry's text, the associated Character structs for the participants in the event, and "bonus" events that
  may modify/add to the message

  Entry bonuses are an addition to what would otherwise be a regular event message. For example, one Death
  event would produce a message like, "<attacker name> killed <victim name>". However, if this Death event was
  followed/preceeded by GainExperience events that described a priority kill and an ended killstreak, with the same
  character IDs and same event timestamps, the message might have some additional text/icons appended to it to describe
  these bonuses

  Alternatively an Entry may describe many consecutive events, like a player healing another player over two ticks, in
  which case "(x2)" would be appended to the regular message.
  """

  import CAI.Guards, only: [is_kill_xp: 1, is_vehicle_bonus_xp: 1]

  alias CAI.Characters
  alias CAI.ESS.{Death, FacilityControl, GainExperience, PlayerFacilityCapture, PlayerFacilityDefend, VehicleDestroy}

  alias CAI.Characters.{Character, PendingCharacter}
  alias CAI.ESS.Helpers
  alias CAIWeb.SessionLive.Entry

  @enforce_keys [:event, :character]
  defstruct event: nil, character: nil, other: :none, count: 1, bonuses: []
  @type t :: %__MODULE__{}

  @type presentable_character :: Character.t() | PendingCharacter.t()

  @doc """
  Create a new Entry struct
  """
  @spec new(event :: map(), character :: presentable_character(), other :: presentable_character() | :none, integer(), [
          map()
        ]) ::
          Entry.t()
  def new(event, character, other \\ :none, count \\ 1, bonuses \\ []) do
    %Entry{event: event, character: character, other: other, count: count, bonuses: bonuses}
  end

  @doc """
  Creates entries from a map of grouped events.

  Given a map of groups, like %{pending_key => %{event: primary_event, bonuses: event_list}}, where pending_key looks
  like {timestamp, character_id, other_id} or {timestamp, world_id, zone_id, facility_id}, create a list of entries.
  """
  def from_groups(grouped, init_entries, character_map) do
    for {_, %{event: e, bonuses: bonuses}} <- grouped, reduce: init_entries do
      acc ->
        # If we didn't find a primary event associated with these bonuses, just put the bonuses back as regular entries.
        if is_nil(e) do
          first_bonus = List.first(bonuses)

          # Exclude FacilityControl events though - these can easily spam the event log.
          if match?(%FacilityControl{}, first_bonus) do
            acc
          else
            {character, other} = map_ids_to_characters(first_bonus, character_map)

            Enum.map(bonuses, &new(&1, character, other)) ++ acc
          end
        else
          {character, other} = map_ids_to_characters(e, character_map)

          [new(e, character, other, 1, bonuses) | acc]
        end
    end
  end

  @doc """
  Fetches a character asynchronously, and returns either the cached `Character` struct or a `PendingCharacter` struct
  with the corresponding state.
  """
  @spec async_fetch_presentable_character(Characters.character_id()) :: presentable_character()
  def async_fetch_presentable_character(character_id) do
    case Characters.fetch_async(character_id) do
      {:ok, character} -> character
      {:fetching, query} -> %PendingCharacter{state: {:loading, query}, character_id: character_id}
      :not_found -> %PendingCharacter{state: :unavailable, character_id: character_id}
      {:error, _error} -> %PendingCharacter{state: :unavailable, character_id: character_id}
    end
  end

  @doc """
  Map ESS events to entries.

  Takes a list of events and returns a list of `Entry`s. This function expects a character map in order to properly map
  the character IDs in the events to `Character` structs. The map keys should the `t:Characters.character_id()`s, and
  the values `t:presentable_character()`s. If a character ID in an event doesn't have a corresponding entry in the
  `character_map`, it will default to a `PendingCharacter` struct with `:state` set to `:unavailable`.
  """
  @spec map([map()], %{Characters.character_id() => presentable_character()}) :: [Entry.t()]
  def map(events, character_map \\ %{}) do
    events
    |> do_map(character_map)
    |> Enum.reverse()
  end

  # entry point
  defp do_map([e | init_events], character_map) do
    {character, other} = map_ids_to_characters(e, character_map)

    do_map([new(e, character, other)], init_events, character_map)
  end

  defp do_map([], _character_map), do: []

  # exit condition (no remaining events)
  defp do_map(mapped, [], _character_map), do: mapped

  # when the prev_e and e timestamps match, let's check for a primary event + the corresponding bonus events, and
  # then condense them
  defp do_map(
         [%Entry{event: %{timestamp: t} = prev_e} | mapped],
         [%{timestamp: t} = e | rem_events],
         character_map
       ) do
    {new_mapped, remaining} =
      condense_event_with_bonuses([prev_e, e | rem_events], mapped, %{}, _target_t = t, character_map)

    do_map(new_mapped, remaining, character_map)
  end

  defp do_map(
         [%Entry{} = prev_entry1, %Entry{count: prev_count} = prev_entry2 | mapped],
         [e | rem_events],
         character_map
       ) do
    if Helpers.consecutive?(prev_entry1.event, prev_entry2.event, prev_entry1.bonuses, prev_entry2.bonuses) do
      do_map([%Entry{prev_entry2 | count: prev_count + 1} | mapped], [e | rem_events], character_map)
    else
      {character, other} = map_ids_to_characters(e, character_map)
      do_map([new(e, character, other), prev_entry1, prev_entry2 | mapped], rem_events, character_map)
    end
  end

  defp do_map(mapped, [e | rem_events], character_map) do
    {character, other} = map_ids_to_characters(e, character_map)
    do_map([new(e, character, other) | mapped], rem_events, character_map)
  end

  defp map_ids_to_characters(%{character_id: character_id, other_id: other_id}, character_map) do
    {get_character(character_map, character_id), get_character(character_map, other_id)}
  end

  defp map_ids_to_characters(%{character_id: character_id, attacker_character_id: attacker_id}, character_map) do
    {get_character(character_map, character_id), get_character(character_map, attacker_id)}
  end

  defp map_ids_to_characters(%{character_id: character_id}, character_map) do
    {get_character(character_map, character_id), :none}
  end

  defp map_ids_to_characters(_event, _character_map) do
    {:none, :none}
  end

  defp get_character(character_map, character_id) do
    Map.get(character_map, character_id, %PendingCharacter{state: :unavailable, character_id: character_id})
  end

  # No more events to iterate
  defp condense_event_with_bonuses([], mapped, grouped, _target_t, character_map) do
    apply_grouped([], mapped, grouped, character_map)
  end

  # If timestamps are different, we're done here
  defp condense_event_with_bonuses(
         [%{timestamp: t} | _] = rem_events,
         mapped,
         grouped,
         target_t,
         character_map
       )
       when t != target_t do
    apply_grouped(rem_events, mapped, grouped, character_map)
  end

  # If `event` is a primary event, or bonus event related to the primary, add it to `grouped` keyed by
  # {timestamp, attacker_id, victim_id} or {timestamp, world_id, zone_id, facility_id}. Otherwise, append `event` to
  # mapped
  defp condense_event_with_bonuses([event | rem_events], mapped, grouped, target_t, character_map) do
    case event do
      # put a death event as the primary event for a grouped entry
      %Death{} ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.attacker_character_id, event.character_id},
            %{event: event, bonuses: []},
            &Map.put(&1, :event, event)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      %GainExperience{experience_id: id} when is_vehicle_bonus_xp(id) ->
        new_grouped =
          Map.update(
            grouped,
            {:vehicle, event.timestamp, event.character_id},
            %{event: nil, bonuses: [event]},
            &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      # put a GE kill XP bonus event for a grouped entry
      %GainExperience{experience_id: id} when is_kill_xp(id) ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.character_id, event.other_id},
            %{event: nil, bonuses: [event]},
            &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      # put a player facility cap/def event as the primary event for a grouped entry
      %mod{} when mod in [PlayerFacilityCapture, PlayerFacilityDefend] ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.world_id, event.zone_id, event.facility_id},
            %{event: event, bonuses: []},
            &Map.put(&1, :event, event)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      # put a facility control for a grouped entry
      %FacilityControl{} ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.world_id, event.zone_id, event.facility_id},
            %{event: nil, bonuses: [event]},
            &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      # put a VehicleDestroy event as the primary event for a grouped entry
      %VehicleDestroy{} ->
        new_grouped =
          Map.update(
            grouped,
            {:vehicle, event.timestamp, event.attacker_character_id},
            %{event: event, bonuses: []},
            &Map.put(&1, :event, event)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character_map)

      # this event seems to be unrelated, so just append it to `mapped`
      _ ->
        {character, other} = map_ids_to_characters(event, character_map)
        new_mapped = [new(event, character, other) | mapped]

        condense_event_with_bonuses(rem_events, new_mapped, grouped, target_t, character_map)
    end
  end

  defp apply_grouped(remaining, mapped, grouped, character_map) do
    new_mapped = from_groups(grouped, mapped, character_map)

    {new_mapped, remaining}
  end
end
