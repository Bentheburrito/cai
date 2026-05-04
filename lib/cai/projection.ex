defmodule CAI.Projection do
  use Ecto.Schema

  @primary_key false
  schema "projections" do
    field :projector, :string, primary_key: true
    field :key, :string, primary_key: true
    field :state, CAI.Projection.Type

    belongs_to :projected_up_to, CAI.Event, foreign_key: :projected_up_to_index, references: :index

    timestamps(type: :utc_datetime_usec)
  end

  @type t() :: %__MODULE__{}
end
