defmodule CAI.Event.PlayerFacilityCapture do
  @moduledoc """
  Ecto schema for PlayerFacilityCapture events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :character_id, :integer
    field :timestamp, :integer
    field :facility_id, :integer
    field :outfit_id, :integer
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
