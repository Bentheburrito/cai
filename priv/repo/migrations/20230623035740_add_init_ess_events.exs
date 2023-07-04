defmodule CAI.Repo.Migrations.AddInitEssEvents do
  use Ecto.Migration

  def change do
    create table(:deaths, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :attacker_character_id, :bigint, primary_key: true
      add :attacker_fire_mode_id, :integer
      add :attacker_loadout_id, :integer
      add :attacker_team_id, :integer
      add :attacker_vehicle_id, :integer
      add :attacker_weapon_id, :integer
      add :character_loadout_id, :integer
      add :is_critical, :boolean
      add :is_headshot, :boolean
      add :team_id, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:gain_experiences) do
      add :amount, :integer
      add :character_id, :bigint
      add :experience_id, :integer
      add :loadout_id, :integer
      add :other_id, :bigint
      add :team_id, :integer
      add :timestamp, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:vehicle_destroys, primary_key: false) do
      add :character_id, :bigint
      add :timestamp, :integer
      add :attacker_character_id, :bigint
      add :attacker_loadout_id, :integer
      add :attacker_team_id, :integer
      add :attacker_vehicle_id, :integer
      add :attacker_weapon_id, :integer
      add :facility_id, :integer
      add :faction_id, :integer
      add :team_id, :integer
      add :vehicle_id, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:player_logouts, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :world_id, :integer
    end

    create table(:player_logins, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :world_id, :integer
    end

    create table(:continent_unlocks) do
      add :metagame_event_id, :integer
      add :nc_population, :integer
      add :previous_faction, :integer
      add :timestamp, :integer
      add :tr_population, :integer
      add :triggering_faction, :integer
      add :vs_population, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:continent_locks) do
      add :metagame_event_id, :integer
      add :nc_population, :integer
      add :previous_faction, :integer
      add :timestamp, :integer
      add :tr_population, :integer
      add :triggering_faction, :integer
      add :vs_population, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:player_facility_defends, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :facility_id, :integer
      add :outfit_id, :bigint
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:player_facility_captures, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :facility_id, :integer
      add :outfit_id, :bigint
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:battle_rank_ups, primary_key: false) do
      add :character_id, :bigint, primary_key: true
      add :timestamp, :integer, primary_key: true
      add :battle_rank, :integer, primary_key: true
      add :world_id, :integer
      add :zone_id, :integer
    end

    create table(:metagame_events) do
      add :experience_bonus, :float
      add :faction_nc, :float
      add :faction_tr, :float
      add :faction_vs, :float
      add :instance_id, :integer
      add :metagame_event_id, :integer
      add :metagame_event_state, :integer
      add :metagame_event_state_name, :string
      add :timestamp, :integer
      add :world_id, :integer
      add :zone_id, :integer
    end

    # create indexes for char IDs on `gain_experiences` and `vehicle_destorys`, since they
    # do not have composite primary keys (the frequency of these events + granularity of the
    # timestamp field (seconds) would mean primary key conflicts).
    create index(:vehicle_destroys, [:character_id])
    create index(:gain_experiences, [:character_id])
    create index(:vehicle_destroys, [:attacker_character_id])
    create index(:gain_experiences, [:other_id])

    # create indexes on the `:timestamp` for quick queries when building a session
    create index(:deaths, [:timestamp])
    create index(:gain_experiences, [:timestamp])
    create index(:vehicle_destroys, [:timestamp])
    create index(:player_logouts, [:timestamp])
    create index(:player_logins, [:timestamp])
    create index(:continent_unlocks, [:timestamp])
    create index(:continent_locks, [:timestamp])
    create index(:player_facility_defends, [:timestamp])
    create index(:player_facility_captures, [:timestamp])
    create index(:battle_rank_ups, [:timestamp])
    create index(:metagame_events, [:timestamp])
  end
end
