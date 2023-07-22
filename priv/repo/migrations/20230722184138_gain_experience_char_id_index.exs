defmodule CAI.Repo.Migrations.GainExperienceCharIdIndex do
  use Ecto.Migration

  def change do
    create index(:gain_experiences, [:character_id])
  end
end
