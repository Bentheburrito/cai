defmodule CAI.ESS.Helpers do
  @moduledoc """
  Helper functions related to ESS events associated characters.
  """

  import Ecto.Query

  alias CAI.Characters
  alias CAI.ESS.PlayerLogout

  require Logger

  @doc """
  Determines if two events are consecutive.

  If the event types and certain fields on the events are the same, returns `true`. The following fields are compared
  (if applicable):
  - character_id
  - attacker_character_id
  - other_id
  - experience_id
  """
  @spec consecutive?(map(), map(), list(), list()) :: boolean()
  def consecutive?(%mod1{} = e1, %mod2{} = e2, bonuses1 \\ [], bonuses2 \\ []) do
    mod1 == mod2 and
      Map.get(e1, :character_id) == Map.get(e2, :character_id) and
      Map.get(e1, :character_loadout_id) == Map.get(e2, :character_loadout_id) and
      Map.get(e1, :attacker_character_id) == Map.get(e2, :attacker_character_id) and
      Map.get(e1, :attacker_loadout_id) == Map.get(e2, :attacker_loadout_id) and
      Map.get(e1, :attacker_weapon_id) == Map.get(e2, :attacker_weapon_id) and
      Map.get(e1, :other_id) == Map.get(e2, :other_id) and
      Map.get(e1, :experience_id) == Map.get(e2, :experience_id) and
      bonuses1 == bonuses2
  end

  @doc """
  Given a character ID and a list of timestamps returned by Characters.get_session_boundaries/1, determine if the
  character is currently online.

  Checks the DB with `Repo.exists?/1`
  """
  @spec online?(Characters.character_id(), [{integer(), integer()}]) :: boolean()
  def online?(character_id, timestamps) do
    # first element of timestamps list, 2nd element of the tuple is the logout timestamp
    latest_timestamp = get_in(timestamps, [Access.at(0), Access.elem(1)]) || 0
    recent? = latest_timestamp > :os.system_time(:second) - Characters.Session.session_timeout_mins() * 60

    logout? =
      PlayerLogout
      |> where([logout], logout.character_id == ^character_id)
      |> where([logout], logout.timestamp == ^latest_timestamp)
      |> CAI.Repo.exists?()

    recent? and not logout?
  end

  @doc """
  Given a character's last known event, determine if the character is currently online.

  Does not require a trip to the DB.
  """
  @spec online?(event :: map() | nil) :: boolean()
  def online?(last_event) do
    case last_event do
      %PlayerLogout{} -> false
      nil -> false
      %{timestamp: timestamp} -> timestamp > :os.system_time(:second) - Characters.Session.session_timeout_mins() * 60
    end
  end

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
