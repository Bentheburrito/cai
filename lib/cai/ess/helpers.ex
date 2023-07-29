defmodule CAI.ESS.Helpers do
  @moduledoc """
  Helper functions related to ESS events associated characters.
  """

  import Ecto.Query

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{Death, GainExperience, PlayerLogout, VehicleDestroy}

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
  @spec online?(Characters.character_id(), [{integer(), integer()}] | (event :: map())) :: boolean()
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
  def online?(last_event) do
    case last_event do
      %PlayerLogout{} -> false
      %{timestamp: timestamp} -> timestamp > :os.system_time(:second) - Characters.Session.session_timeout_mins() * 60
    end
  end

  @doc """
  Gets the `Character.t()` for the other character in this interaction (if there is one).

  Given `this_character_id`, an ESS event, and (optionally) a fetch function, will get the other Character for the
  event. Will return `:noop` if the event does not contain a second character ID. If the fetch function does not return
  `{:ok, Character.t()}`, this function will return `{:unavailable, other_id}`
  """
  def get_other_character(this_char_id, event, fetch_fn \\ &Characters.fetch/1)

  def get_other_character(this_char_id, event, fetch_fn) do
    case do_get_other_character(this_char_id, event, fetch_fn) do
      :noop ->
        :noop

      {{:ok, %Character{} = other}, _other_id} ->
        other

      {{:ok, :not_found}, other_id} ->
        Logger.info("Character ID not_found: #{other_id}")
        {:unavailable, other_id}

      {reason, other_id} ->
        if CAI.Guards.character_id?(other_id) do
          Logger.warning("Couldn't fetch other character (ID #{inspect(other_id)}) for an event: #{inspect(reason)}")
        end

        {:unavailable, other_id}
    end
  end

  defp do_get_other_character(this_char_id, %GainExperience{character_id: this_char_id} = ge, fetch_fn) do
    {fetch_fn.(ge.other_id), ge.other_id}
  end

  defp do_get_other_character(this_char_id, %GainExperience{other_id: this_char_id} = ge, fetch_fn) do
    {fetch_fn.(ge.character_id), ge.character_id}
  end

  defp do_get_other_character(this_char_id, %mod{character_id: this_char_id} = e, fetch_fn)
       when mod in [Death, VehicleDestroy] do
    {fetch_fn.(e.attacker_character_id), e.attacker_character_id}
  end

  defp do_get_other_character(this_char_id, %mod{attacker_character_id: this_char_id} = e, fetch_fn)
       when mod in [Death, VehicleDestroy] do
    {fetch_fn.(e.character_id), e.character_id}
  end

  defp do_get_other_character(_, _, _), do: :noop
end
