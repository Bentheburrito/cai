defmodule CAI.Repo.Migrations.NewEventsBasedSchema do
  use Ecto.Migration

  def change do
    create table(:static_data, primary_key: false) do
      add :kind, :string, primary_key: true
      add :id, :integer, primary_key: true
      add :data, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:events, primary_key: false) do
      add :index, :serial, primary_key: true, autoincrement: true
      add :struct, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:projections, primary_key: false) do
      add :projector, :string, primary_key: true
      add :key, :string, primary_key: true
      add :state, :map, null: false
      add :projected_up_to_index, references(:events, column: :index), null: true

      timestamps(type: :utc_datetime_usec)
    end
  end
end
