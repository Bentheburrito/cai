defmodule CAI.Macros do
  @moduledoc false

  @doc """
  Create a function that gets a specific `field_type` of static data. E.g. `static_getter(:vehicle)` will create a
  function called `get_vehicle/1` that takes an ID and searches the static data cache for `{:vehicle, vehicle_id}`.
  """
  defmacro static_getter(field_type) do
    quote do
      require Logger

      @doc """
      Gets a #{unquote(field_type)} from the static data cache. Returns `nil` if there is no entry under `id`.
      """
      def unquote(:"get_#{field_type}")(id) do
        case Cachex.get(CAI.Cachex.static_data(), {unquote(field_type), id}) do
          {:ok, value} ->
            value

          unexpected ->
            Logger.warning(
              "Got unexpected value when trying to access the static data cache from `CAI.get_#{unquote(field_type)}/1`: #{inspect(unexpected)}"
            )

            nil
        end
      end
    end
  end
end
