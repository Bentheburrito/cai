defmodule CAI.ESS.BattleRankUp do
  @moduledoc """
  Ecto schema for BattleRankUp events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  schema "battle_rank_ups" do
    field :character_id, :integer
    field :timestamp, :integer
    field :battle_rank, :integer
    field :world_id, :integer
    field :zone_id, :integer
  end

  def changeset(event, params \\ %{}) do
    field_list =
      :fields
      |> __MODULE__.__schema__()
      |> List.delete(:id)

    event
    |> cast(params, field_list)
    |> unique_constraint([:character_id, :timestamp, :battle_rank], name: "battle_rank_ups_pkey")
  end
end
