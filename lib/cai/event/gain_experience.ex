defmodule CAI.Event.GainExperience do
  @moduledoc """
  Ecto schema for GainExperience events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :amount, :integer
    field :character_id, :integer
    field :experience_id, :integer
    field :loadout_id, :integer
    field :other_id, :integer
    field :team_id, :integer
    field :timestamp, :integer
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
