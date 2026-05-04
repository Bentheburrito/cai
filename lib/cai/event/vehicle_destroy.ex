defmodule CAI.Event.VehicleDestroy do
  @moduledoc """
  Ecto schema for VehicleDestroy events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :character_id, :integer
    field :timestamp, :integer
    field :attacker_character_id, :integer
    field :attacker_loadout_id, :integer
    field :attacker_team_id, :integer
    field :attacker_vehicle_id, :integer
    field :attacker_weapon_id, :integer
    field :facility_id, :integer
    field :faction_id, :integer
    field :team_id, :integer
    field :vehicle_id, :integer
    field :world_id, :integer
    field :zone_id, :integer
  end

  defimpl JSON.Encoder do
    def encode(event, opts) do
      {:ok, dumped_event} = CAI.Event.Type.dump(event)
      JSON.encode!(dumped_event, opts)
    end
  end
end
