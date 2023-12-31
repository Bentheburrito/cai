defmodule CAI.Characters.PendingCharacter do
  @moduledoc """
  A placeholder struct for pending `Character`s.

  Contains additional fields: `:type` and `:query`.
  - `:type` indicates the current state of the query. Its value can be one of:
    - `{:loading, query}`, where `query` is the query used to fetch the character.
    - `:unavailable`. This signifies the character could not be found, possibly due to a Census error.
  Defaults to `:unavailable`.
  """
  alias PS2.API.Query

  @type t() :: %__MODULE__{
          character_id: integer(),
          name_first: String.t(),
          faction_id: integer(),
          state: {:loading, Query.t()} | :unavailable
        }
  @enforce_keys [:state]
  defstruct character_id: 0, name_first: "[Name Unavailable]", faction_id: 0, state: :unavailable
end
