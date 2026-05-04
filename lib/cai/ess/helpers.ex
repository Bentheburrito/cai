defmodule CAI.ESS.Helpers do
  @moduledoc """
  Helper functions related to ESS events associated characters.
  """

  require Logger

  @doc """
  Gets the `t:Characters.character_id()` for the other character in this interaction (or `:none` if this event does not
  have a secondary character ID).
  """
  def get_other_character_id(this_char_id, %{character_id: this_char_id, other_id: _} = e), do: e.other_id
  def get_other_character_id(this_char_id, %{other_id: this_char_id} = e), do: e.character_id

  def get_other_character_id(this_char_id, %{character_id: this_char_id, attacker_character_id: _} = e),
    do: e.attacker_character_id

  def get_other_character_id(this_char_id, %{attacker_character_id: this_char_id} = e), do: e.character_id
  def get_other_character_id(_, _), do: :none
end
