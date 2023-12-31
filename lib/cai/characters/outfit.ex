defmodule CAI.Characters.Outfit do
  @moduledoc """
  Ecto embedded schema for a character's outfit
  """

  alias CAI.Characters.Outfit

  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false

  embedded_schema do
    field :outfit_id, :integer
    field :member_since_date, :utc_datetime
    field :name, :string
    field :alias, :string, default: ""
    field :time_created_date, :utc_datetime
    field :leader_character_id, :integer
  end

  @fields [
    :outfit_id,
    :member_since_date,
    :name,
    :alias,
    :time_created_date,
    :leader_character_id
  ]

  def changeset(outfit, census_res \\ %{}) do
    params =
      census_res
      |> Map.put("member_since_date", format_census_date(census_res["member_since_date"]))
      |> Map.put("time_created_date", format_census_date(census_res["time_created_date"]))

    outfit
    |> cast(params, @fields)
    # Aliases are apparently not required
    |> validate_required(@fields |> List.delete(:alias) |> List.delete(:member_since_date))
  end

  def alias_or_name(%Outfit{alias: alias}) when alias not in [nil, ""], do: "[" <> alias <> "]"
  def alias_or_name(%Outfit{name: name}), do: name

  defp format_census_date(date_string) when date_string in [nil, ""], do: nil
  defp format_census_date(date_string), do: date_string <> "Z"
end
