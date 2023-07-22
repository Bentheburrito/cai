defmodule CAI.Repo.Migrations.AlterEssIndices do
  use Ecto.Migration

  def change do
    drop constraint(:deaths, :deaths_pkey)
    alter table(:gain_experiences), do: remove(:id)
    drop constraint(:player_logins, :player_logins_pkey)
    drop constraint(:player_logouts, :player_logouts_pkey)
    drop constraint(:continent_unlocks, :continent_unlocks_pkey)
    alter table(:continent_unlocks), do: remove(:id)
    drop constraint(:continent_locks, :continent_locks_pkey)
    alter table(:continent_locks), do: remove(:id)
    drop constraint(:player_facility_defends, :player_facility_defends_pkey)
    drop constraint(:player_facility_captures, :player_facility_captures_pkey)
    drop constraint(:battle_rank_ups, :battle_rank_ups_pkey)
    drop constraint(:metagame_events, :metagame_events_pkey)
    alter table(:metagame_events), do: remove(:id)
    drop index(:vehicle_destroys, [:character_id])
    drop index(:gain_experiences, [:character_id])
    drop index(:vehicle_destroys, [:attacker_character_id])
    drop index(:gain_experiences, [:other_id])
    drop constraint(:facility_controls, :facility_controls_pkey)
    create index(:facility_controls, [:timestamp])
  end
end
