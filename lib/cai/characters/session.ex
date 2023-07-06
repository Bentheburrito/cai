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

  alias CAI.{ESS, Repo}
  alias CAI.Characters.Session

  alias CAI.ESS.{
    Death,
    GainExperience,
    BattleRankUp,
    PlayerFacilityCapture,
    PlayerFacilityDefend,
    PlayerLogin,
    PlayerLogout,
    VehicleDestroy
  }

  def session_timeout_mins, do: @session_timeout_mins
  def session_timeout_ms, do: @session_timeout_mins * 60 * 1000

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
  def build(character_id, login..logout) do
    build(character_id, login, logout)
  end

  def build(character_id, login, logout) when is_integer(login) and is_integer(logout) do
    changeset =
      %Session{}
      |> cast(%{"character_id" => character_id}, [:character_id])
      |> validate_required([:character_id])

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
      put_embed(changeset, field, embed)
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
    where_clause =
      case module do
        GainExperience ->
          dynamic(
            [e],
            (field(e, :character_id) == ^character_id or
               field(e, :other_id) == ^character_id) and
              (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
          )

        mod when mod in [Death, VehicleDestroy] ->
          dynamic(
            [e],
            (field(e, :character_id) == ^character_id or
               field(e, :attacker_character_id) == ^character_id) and
              (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
          )

        _ ->
          dynamic(
            [e],
            field(e, :character_id) == ^character_id and
              (field(e, :timestamp) >= ^login and field(e, :timestamp) <= ^logout)
          )
      end

    Repo.all(from(e in module, select: e, where: ^where_clause))
  end

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
