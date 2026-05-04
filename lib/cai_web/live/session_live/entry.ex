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

  alias CAI.Characters

  alias CAI.Characters.{Character, PendingCharacter}
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
          if match?(%{}, first_bonus) do
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

  def map_entries(entries, character_map \\ %{}) do
    Enum.map(entries, fn entry ->
      {character, other} = map_ids_to_characters(entry.event, character_map)
      Entry.new(entry.event, character, other, entry.count, entry.addl_events)
    end)
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
end
