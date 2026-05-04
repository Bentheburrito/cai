defmodule CAI.Cachex.StaticData do
  use Ecto.Schema

  @primary_key false
  schema "static_data" do
    field :kind, Ecto.Enum, values: [:vehicle, :weapon, :xp, :facility], primary_key: true
    field :id, :integer, primary_key: true
    field :data, :map

    timestamps(type: :utc_datetime_usec)
  end
end
