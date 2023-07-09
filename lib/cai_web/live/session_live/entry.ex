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

  alias CAI.Characters.Character
  alias CAIWeb.SessionLive.Entry

  @enforce_keys [:event, :character]
  defstruct event: nil, character: nil, other: :none, count: 1, bonuses: []
  @type t :: %__MODULE__{}

  @doc """
  Create a new Entry struct
  """
  @spec new(event :: map(), character :: Character.t(), other :: Character.t() | :none, integer(), list(map())) :: Entry.t()
  def new(event, character, other \\ :none, count \\ 1, bonuses \\ []) do
    %Entry{event: event, character: character, other: other, count: count, bonuses: bonuses}
  end
end
