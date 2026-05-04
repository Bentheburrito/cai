defmodule CAI.Event.Type do
  use Ecto.Type

  def type, do: :map

  def cast(%{"event_name" => event_name} = attrs) do
    event_module =
      case event_name do
        "Elixir.CAI.Event." <> _ -> String.to_existing_atom(event_name)
        _ -> Module.safe_concat("CAI.Event", event_name)
      end

    event_module
    |> struct!()
    |> Ecto.Changeset.cast(attrs, event_module.__schema__(:fields))
    |> Ecto.Changeset.apply_action(:insert)
  end

  def cast(%_mod{} = event), do: {:ok, event}
  def cast(_), do: :error

  def load(data) when is_map(data), do: cast(data)

  def dump(%mod{} = event), do: {:ok, event |> Map.from_struct() |> Map.put(:event_name, mod)}
  def dump(_), do: :error
end
