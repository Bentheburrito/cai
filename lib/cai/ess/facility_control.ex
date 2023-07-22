defmodule CAI.ESS.FacilityControl do
  @moduledoc """
  Ecto schema for FacilityControl events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  schema "facility_controls" do
    field :timestamp, :integer
    field :facility_id, :integer
    field :world_id, :integer
    field :new_faction_id, :integer
    field :duration_held, :integer
    field :old_faction_id, :integer
    field :outfit_id, :integer
    field :zone_id, :integer
  end

  def changeset(event, params \\ %{}) do
    field_list =
      :fields
      |> __MODULE__.__schema__()
      |> List.delete(:id)

    event
    |> cast(params, field_list)
    |> unique_constraint([:timestamp, :facility_id, :world_id, :new_faction_id], name: "facility_controls_pkey")
  end
end
