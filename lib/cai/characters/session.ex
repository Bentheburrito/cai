defmodule CAI.Characters.Session do
  @session_timeout_mins 30
  @moduledoc """
  A character's game session.

  A particular session is defined by the ESS events between a PlayerLogin, PlayerLogout pair (and including the pair),
  where the login timestamp is earlier or equal to the logout timestamp. However, due to occassional flakiness in the
  ESS, there is no guarantee the socket will receive all (or any) of the login/logout events. Therefore, a session can
  also be defined as a group of events with a #{@session_timeout_mins} minute period of inactivity before the first
  event, and after the last event. We only consider the most frequent events to gauge activity: PlayerLogin,
  GainExperience, and Deaths.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CAI.ESS

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
    embeds_many(:login, ESS.PlayerLogin)
    embeds_many(:logout, ESS.PlayerLogout)

    timestamps()
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
