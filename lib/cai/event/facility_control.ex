defmodule CAI.Event.FacilityControl do
  @moduledoc """
  Ecto schema for FacilityControl events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :timestamp, :integer
    field :facility_id, :integer
    field :world_id, :integer
    field :new_faction_id, :integer
    field :duration_held, :integer
    field :old_faction_id, :integer
    field :outfit_id, :integer
    field :zone_id, :integer
  end

  defimpl JSON.Encoder do
    def encode(event, opts) do
      {:ok, dumped_event} = CAI.Event.Type.dump(event)
      JSON.encode!(dumped_event, opts)
    end
  end
end
