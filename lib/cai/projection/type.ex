defmodule CAI.Projection.Type do
  use Ecto.Type

  def type, do: :map

  def cast(%{"projector" => "Elixir." <> _ = projector_str} = attrs) do
    projector = String.to_existing_atom(projector_str)
    {:ok, projector.load(attrs)}
  end

  def cast(%_mod{} = projection_state), do: {:ok, projection_state}
  def cast(_), do: :error

  def load(data) when is_map(data), do: cast(data)

  def dump(%mod{} = projection_state),
    do: {:ok, projection_state |> Map.from_struct() |> Map.put(:projector, to_string(mod))}

  def dump(_), do: :error
end
