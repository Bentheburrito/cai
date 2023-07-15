defmodule CAI.ESS.Helpers do
  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{GainExperience, Death, VehicleDestroy}

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
  @spec consecutive?(map(), map()) :: boolean()
  def consecutive?(%mod1{} = e1, %mod2{} = e2) do
    mod1 == mod2 and
      Map.get(e1, :character_id) == Map.get(e2, :character_id) and
      Map.get(e1, :attacker_character_id) == Map.get(e2, :attacker_character_id) and
      Map.get(e1, :other_id) == Map.get(e2, :other_id) and
      Map.get(e1, :experience_id) == Map.get(e2, :experience_id)
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
        if CAI.character_id?(other_id) do
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
