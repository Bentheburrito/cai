defmodule CAI.Characters.Session do
  @session_timeout_mins 30
  @moduledoc """
  A character's game session.

  A particular session is defined by the ESS events between a PlayerLogin, PlayerLogout pair (and including the pair),
  where the login timestamp is earlier or equal to the logout timestamp. However, due to occassional flakiness in the
  ESS, there is no guarantee the socket will receive all (or any) of the login/logout events. Therefore, a session can
  also be defined as a group of events with a #{@session_timeout_mins} minute period of inactivity before the first
  event, and after the last event. We only consider the most frequent events to gauge activity: PlayerLogin,
  GainExperience, and Death.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require CAI.Guards

  alias CAI.Characters.Session
  alias CAI.{ESS, Repo}

  alias CAI.ESS.{
    BattleRankUp,
    Death,
    GainExperience,
    PlayerFacilityCapture,
    PlayerFacilityDefend,
    PlayerLogin,
    PlayerLogout,
    VehicleDestroy
  }

  def session_timeout_mins, do: @session_timeout_mins
  def session_timeout_ms, do: @session_timeout_mins * 60 * 1000

  def aggregate_fields do
    [
      :kill_count,
      :kill_hs_count,
      :kill_hs_ivi_count,
      :kill_ivi_count,
      :death_ivi_count,
      :death_count,
      :revive_count,
      :vehicle_kill_count,
      :vehicle_death_count,
      :nanites_destroyed,
      :nanites_lost,
      :xp_earned
    ]
  end

  embedded_schema do
    field(:character_id, :integer)
    # aggregate data
    field(:kill_count, :integer, default: 0)
    field(:kill_hs_count, :integer, default: 0)
    field(:kill_hs_ivi_count, :integer, default: 0)
    field(:kill_ivi_count, :integer, default: 0)
    field(:death_ivi_count, :integer, default: 0)
    field(:death_count, :integer, default: 0)
    field(:revive_count, :integer, default: 0)
    field(:vehicle_kill_count, :integer, default: 0)
    field(:vehicle_death_count, :integer, default: 0)
    field(:nanites_destroyed, :integer, default: 0)
    field(:nanites_lost, :integer, default: 0)
    field(:xp_earned, :integer, default: 0)
    # embedded data
    embeds_many(:battle_rank_ups, ESS.BattleRankUp)
    embeds_many(:deaths, ESS.Death)
    embeds_many(:gain_experiences, ESS.GainExperience)
    embeds_many(:player_facility_captures, ESS.PlayerFacilityCapture)
    embeds_many(:player_facility_defends, ESS.PlayerFacilityDefend)
    embeds_many(:vehicle_destroys, ESS.VehicleDestroy)
    embeds_one(:login, ESS.PlayerLogin)
    embeds_one(:logout, ESS.PlayerLogout)

    timestamps()
  end

  @doc """
  Builds a session from the given character ID and login/logout unix timestamps.

  Returns a session struct.

  Use this function over `changeset/2` to get the initial session using database values.
  Use `changeset/2` when you want to update a session after it has been built. `changeset/2` should really only be used
  if the session is ongoing/live.
  """
  @spec build(CAI.Characters.character_id(), Range.t()) :: {:ok, %__MODULE__{}} | {:error, Changeset.t()}
  def build(character_id, login..logout) do
    build(character_id, login, logout)
  end

  @spec build(CAI.Characters.character_id(), integer(), integer()) :: {:ok, %__MODULE__{}} | {:error, Changeset.t()}
  def build(character_id, login, logout) when is_integer(login) and is_integer(logout) do
    %Session{}
    |> cast(%{character_id: character_id}, [:character_id])
    |> validate_required([:character_id])
    |> case do
      %{valid?: true} = changeset ->
        do_build(character_id, changeset, login, logout)

      invalid_cs ->
        {:error, invalid_cs}
    end
  end

  defp do_build(character_id, changeset, login, logout) do
    [
      {:gain_experiences, GainExperience},
      {:deaths, Death},
      {:vehicle_destroys, VehicleDestroy},
      {:player_facility_captures, PlayerFacilityCapture},
      {:player_facility_defends, PlayerFacilityDefend},
      {:battle_rank_ups, BattleRankUp},
      {:login, PlayerLogin},
      {:logout, PlayerLogout}
    ]
    |> Enum.reduce(changeset, fn {field, module}, changeset ->
      embed = build_embed(module, character_id, login, logout)

      changeset
      |> put_embed(field, embed)
      |> put_aggregates(embed)
    end)
    |> apply_action(:update)
  end

  @embedded_once [PlayerLogin, PlayerLogout]
  defp build_embed(module, character_id, login, logout) when module in @embedded_once do
    timestamp = if module == PlayerLogin, do: login, else: logout

    Repo.one(
      from(log in module,
        select: log,
        where: log.character_id == ^character_id and log.timestamp == ^timestamp,
        limit: 1
      )
    )
  end

  defp build_embed(module, character_id, login, logout) do
    where_clause = build_embed_where_clause(module, character_id, login, logout)

    Repo.all(from(e in module, select: e, where: ^where_clause))
  end

  defp build_embed_where_clause(GainExperience, character_id, login, logout) do
    dynamic(
      [e],
      (field(e, :character_id) == ^character_id or
         field(e, :other_id) == ^character_id) and
        (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
    )
  end

  defp build_embed_where_clause(mod, character_id, login, logout) when mod in [Death, VehicleDestroy] do
    dynamic(
      [e],
      (field(e, :character_id) == ^character_id or
         field(e, :attacker_character_id) == ^character_id) and
        (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
    )
  end

  defp build_embed_where_clause(_, character_id, login, logout) do
    dynamic(
      [e],
      field(e, :character_id) == ^character_id and
        (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
    )
  end

  defp put_aggregates(changeset, event_list) when is_list(event_list) do
    params = Enum.reduce(event_list, %{}, &put_aggregate_event(&1, &2, changeset.changes.character_id))

    fields = Map.keys(params)
    cast(changeset, params, fields)
  end

  # PlayerLogin/Logout will not be a list, so just return changeset since they don't give aggregate results
  defp put_aggregates(changeset, _), do: changeset

  def put_aggregate_event(%GainExperience{} = ge, params, character_id) do
    revive_add = if CAI.Guards.is_revive_xp(ge.experience_id) and ge.character_id == character_id, do: 1, else: 0

    params
    |> Map.update(:revive_count, revive_add, &(&1 + revive_add))
    |> Map.update(:xp_earned, ge.amount, &(&1 + ge.amount))
  end

  def put_aggregate_event(%Death{} = death, params, character_id) do
    if death.character_id == character_id do
      death_ivi_add = if CAI.get_weapon(death.attacker_weapon_id)["sanction"] == "infantry", do: 1, else: 0

      params
      |> Map.update(:death_count, 1, &(&1 + 1))
      |> Map.update(:death_ivi_count, death_ivi_add, &(&1 + death_ivi_add))
    else
      kill_ivi_add = if CAI.get_weapon(death.attacker_weapon_id)["sanction"] == "infantry", do: 1, else: 0
      kill_hs_add = if death.is_headshot, do: 1, else: 0
      kill_hs_ivi_add = if kill_ivi_add == 1 and kill_hs_add == 1, do: 1, else: 0

      params
      |> Map.update(:kill_count, 1, &(&1 + 1))
      |> Map.update(:kill_ivi_count, kill_ivi_add, &(&1 + kill_ivi_add))
      |> Map.update(:kill_hs_count, kill_hs_add, &(&1 + kill_hs_add))
      |> Map.update(:kill_hs_ivi_count, kill_hs_ivi_add, &(&1 + kill_hs_ivi_add))
    end
  end

  def put_aggregate_event(%VehicleDestroy{} = vd, params, character_id) do
    vehicle_cost = CAI.get_vehicle(vd.vehicle_id)["cost"]

    if vd.character_id == character_id do
      params
      |> Map.update(:vehicle_death_count, 1, &(&1 + 1))
      |> Map.update(:nanites_lost, vehicle_cost, &(&1 + vehicle_cost))
    else
      params
      |> Map.update(:vehicle_kill_count, 1, &(&1 + 1))
      |> Map.update(:nanites_destroyed, vehicle_cost, &(&1 + vehicle_cost))
    end
  end

  def put_aggregate_event(_, params, _), do: params

  @doc false
  def changeset(session, attrs) do
    field_list =
      :fields
      |> __MODULE__.__schema__()
      |> List.delete(:id)

    session
    |> cast(attrs, field_list)
    |> validate_required([:character_id])
    |> cast_embed(:battle_rank_ups, with: &ESS.BattleRankUp.changeset/2)
    |> cast_embed(:deaths, with: &ESS.Death.changeset/2)
    |> cast_embed(:gain_experiences, with: &ESS.GainExperience.changeset/2)
    |> cast_embed(:player_facility_captures, with: &ESS.PlayerFacilityCapture.changeset/2)
    |> cast_embed(:player_facility_defends, with: &ESS.PlayerFacilityDefend.changeset/2)
    |> cast_embed(:vehicle_destroys, with: &ESS.VehicleDestroy.changeset/2)
    |> cast_embed(:login, with: &ESS.PlayerLogin.changeset/2)
    |> cast_embed(:logout, with: &ESS.PlayerLogout.changeset/2)
  end
end
