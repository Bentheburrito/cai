defmodule CAI.Repo.Migrations.AddFacilityControls do
  use Ecto.Migration

  def change do
    create table(:facility_controls, primary_key: false) do
      add :timestamp, :integer, primary_key: true
      add :facility_id, :integer, primary_key: true
      add :world_id, :integer, primary_key: true
      add :new_faction_id, :integer, primary_key: true
      add :duration_held, :integer
      add :old_faction_id, :integer
      add :outfit_id, :bigint
      add :zone_id, :integer
    end
  end
end
