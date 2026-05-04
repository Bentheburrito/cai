defmodule CAI.Event do
  use Ecto.Schema

  @primary_key {:index, :id, autogenerate: true}
  schema "events" do
    field :struct, CAI.Event.Type

    timestamps(type: :utc_datetime_usec)
  end

  @type t() :: %__MODULE__{
          index: non_neg_integer(),
          struct: struct(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
