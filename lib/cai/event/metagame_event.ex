defmodule CAI.Event.MetagameEvent do
  @moduledoc """
  Ecto schema for MetagameEvent events.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :experience_bonus, :float
    field :faction_nc, :float
    field :faction_tr, :float
    field :faction_vs, :float
    field :instance_id, :integer
    field :metagame_event_id, :integer
    field :metagame_event_state, :integer
    field :metagame_event_state_name, :string
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
