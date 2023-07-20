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

  import CAI, only: [is_kill_xp: 1]

  alias CAI.ESS.FacilityControl
  alias CAI.ESS.PlayerFacilityCapture
  alias CAI.ESS.PlayerFacilityDefend
  alias CAI.Characters
  alias CAI.ESS.{GainExperience, Death}

  alias CAI.Characters.Character
  alias CAI.ESS.Helpers
  alias CAIWeb.SessionLive.Entry

  @enforce_keys [:event, :character]
  defstruct event: nil, character: nil, other: :none, count: 1, bonuses: []
  @type t :: %__MODULE__{}

  @doc """
  Create a new Entry struct
  """
  @spec new(event :: map(), character :: Character.t(), other :: Character.t() | :none, integer(), [map()]) :: Entry.t()
  def new(event, character, other \\ :none, count \\ 1, bonuses \\ []) do
    %Entry{event: event, character: character, other: other, count: count, bonuses: bonuses}
  end

  @doc """
  Creates entries from a map of grouped events.

  Given a map of groups, like %{pending_key => %{event: primary_event, bonuses: event_list}}, where pending_key looks
  like {timestamp, character_id, other_id} or {timestamp, world_id, zone_id, facility_id}, create a list of entries.
  """
  def from_groups(grouped, init_entries, character, other_char_map) do
    for {_, %{event: e, bonuses: bonuses}} <- grouped, reduce: init_entries do
      acc ->
        # If we didn't find a primary event associated with these bonuses, just put the bonuses back as regular entries.
        if is_nil(e) do
          other =
            Helpers.get_other_character(character.character_id, List.first(bonuses), &Map.fetch(other_char_map, &1))

          Enum.map(bonuses, &new(&1, character, other)) ++ acc
        else
          other = Helpers.get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))
          [new(e, character, other, 1, bonuses) | acc]
        end
    end
  end

  @doc """
  Map ESS events to entries.

  Fetches all other Characters involved in the given events in (at most) one Census query.
  """
  @spec map([map()], session_character :: Character.t()) :: [Entry.t()]
  def map(events, character) do
    other_character_ids =
      Stream.flat_map(
        events,
        &(Map.take(&1, [:character_id, :attacker_character_id, :other_id]) |> Map.values())
      )
      |> MapSet.new()
      |> MapSet.delete(nil)
      |> MapSet.delete(0)
      |> MapSet.delete(character.character_id)

    other_character_map = other_character_ids |> Characters.get_many() |> Map.put(character.character_id, character)

    events
    |> map(character, other_character_map)
    |> Enum.reverse()
  end

  # entry point
  defp map([e | init_events], character, other_char_map) do
    other = Helpers.get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))

    map([new(e, character, other)], init_events, character, other_char_map)
  end

  # exit condition (no remaining events)
  defp map(mapped, [], _character, _other_char_map), do: mapped

  # when the prev_e and e timestamps match, let's check for a primary event + the corresponding bonus events, and
  # then condense them
  defp map(
         [%Entry{event: %{timestamp: t} = prev_e} | mapped],
         [%{timestamp: t} = e | rem_events],
         character,
         other_char_map
       ) do
    {new_mapped, remaining} =
      condense_event_with_bonuses([prev_e, e | rem_events], mapped, %{}, _target_t = t, character, other_char_map)

    map(new_mapped, remaining, character, other_char_map)
  end

  defp map(
         [%Entry{event: prev_e1} = prev_entry1, %Entry{event: prev_e2, count: prev_count} = prev_entry2 | mapped],
         [e | rem_events],
         character,
         other_char_map
       ) do
    if Helpers.consecutive?(prev_e1, prev_e2) do
      map([%Entry{prev_entry2 | count: prev_count + 1} | mapped], [e | rem_events], character, other_char_map)
    else
      other = Helpers.get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))
      map([new(e, character, other), prev_entry1, prev_entry2 | mapped], rem_events, character, other_char_map)
    end
  end

  defp map(mapped, [e | rem_events], character, other_char_map) do
    other = Helpers.get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))
    map([new(e, character, other) | mapped], rem_events, character, other_char_map)
  end

  # No more events to iterate
  defp condense_event_with_bonuses([], mapped, grouped, _target_t, character, other_char_map) do
    apply_grouped([], mapped, grouped, character, other_char_map)
  end

  # If timestamps are different, we're done here
  defp condense_event_with_bonuses(
         [%{timestamp: t} | _] = rem_events,
         mapped,
         grouped,
         target_t,
         character,
         other_char_map
       )
       when t != target_t do
    apply_grouped(rem_events, mapped, grouped, character, other_char_map)
  end

  # If `event` is a primary event, or bonus event related to the primary, add it to `grouped` keyed by
  # {timestamp, attacker_id, victim_id} or {timestamp, world_id, zone_id, facility_id}. Otherwise, append `event` to
  # mapped
  defp condense_event_with_bonuses([event | rem_events], mapped, grouped, target_t, character, other_char_map) do
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

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # put a GE kill XP bonus event for a grouped entry
      %GainExperience{experience_id: id} when is_kill_xp(id) ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.character_id, event.other_id},
            %{event: nil, bonuses: [event]},
            &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # put a player facility cap/def event as the primary event for a grouped entry
      %mod{} when mod in [PlayerFacilityCapture, PlayerFacilityDefend] ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.world_id, event.zone_id, event.facility_id},
            %{event: event, bonuses: []},
            &Map.put(&1, :event, event)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # put a facility control for a grouped entry
      %FacilityControl{} ->
        new_grouped =
          Map.update(
            grouped,
            {event.timestamp, event.world_id, event.zone_id, event.facility_id},
            %{event: nil, bonuses: [event]},
            &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
          )

        condense_event_with_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # this event seems to be unrelated, so just append it to `mapped`
      _ ->
        other = Helpers.get_other_character(character.character_id, event, &Map.fetch(other_char_map, &1))
        new_mapped = [new(event, character, other) | mapped]

        condense_event_with_bonuses(rem_events, new_mapped, grouped, target_t, character, other_char_map)
    end
  end

  defp apply_grouped(remaining, mapped, grouped, character, other_char_map) do
    new_mapped = from_groups(grouped, mapped, character, other_char_map)

    {new_mapped, remaining}
  end
end
