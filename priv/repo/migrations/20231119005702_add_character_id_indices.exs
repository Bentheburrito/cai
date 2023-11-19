defmodule CAI.Repo.Migrations.AddCharacterIdIndices do
  use Ecto.Migration
  @disable_migration_lock true

  @disable_ddl_transaction true
  # from the Ecto docs ^: Migrations can be forced to run outside
  # a transaction by setting the @disable_ddl_transaction module
  # attribute to true...Since running migrations outside a transaction
  # can be dangerous, consider performing very few operations in such
  # migrations.

  def change do
    create index(:deaths, [:character_id], concurrently: true)
    create index(:vehicle_destroys, [:character_id], concurrently: true)
    create index(:player_facility_captures, [:character_id], concurrently: true)
    create index(:player_facility_defends, [:character_id], concurrently: true)
    create index(:player_logins, [:character_id], concurrently: true)
    create index(:player_logouts, [:character_id], concurrently: true)
  end
end
