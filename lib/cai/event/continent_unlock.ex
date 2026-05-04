defmodule CAI.Event.ContinentUnlock do
  @moduledoc """
  Ecto schema for ContinentUnlock events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :metagame_event_id, :integer
    field :nc_population, :integer
    field :previous_faction, :integer
    field :timestamp, :integer
    field :tr_population, :integer
    field :triggering_faction, :integer
    field :vs_population, :integer
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
