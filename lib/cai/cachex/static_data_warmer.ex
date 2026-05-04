defmodule CAI.Cachex.StaticDataWarmer do
  @moduledoc """
  """
  use Cachex.Warmer

  import CAI.Cachex

  alias CAI.Cachex.StaticData
  alias CAI.Cachex.StaticDataWarmer.Getters
  alias CAI.Repo

  require Logger

  @max_attempts 3

  @impl true
  def interval, do: :timer.hours(static_data_interval_hours())

  @doc """
  """
  @impl true
  def execute(_) do
    case Repo.all(StaticData) do
      [] ->
        Logger.info("No static data in DB, attempting to fetch...")
        fetch_data()

      [%StaticData{inserted_at: inserted_at} | _] = data ->
        if Date.compare(Date.utc_today(), inserted_at) == :gt do
          fetch_data()
        else
          Logger.info("Successfully loaded static data from DB")
          {:ok, Enum.map(data, &{{&1.kind, &1.id}, &1.data})}
        end
    end
  end

  defp fetch_data do
    case query_static_data() do
      {:ok, cache_map} ->
        {count, data} =
          Repo.insert_all(StaticData, Enum.map(cache_map, &cache_entry_to_attrs/1),
            returning: true,
            on_conflict: :replace_all,
            conflict_target: [:kind, :id]
          )

        Logger.info("Successfully fetched and saved static data (#{count})")
        {:ok, Enum.map(data, &{{&1.kind, &1.id}, &1.data})}

      {:error, error} ->
        Logger.error("Failed to query_static_data: #{inspect(error)}")
    end
  end

  defp cache_entry_to_attrs({{kind, id}, data}),
    do: %{kind: kind, id: id, data: data, inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}

  defp query_static_data do
    # Outer ok tuple is the result of the task from Task.async_stream, the inner ok tuple is from the Getters fxns
    reducer = fn
      {:ok, {:ok, entries}}, acc -> {:cont, Map.merge(acc, entries)}
      {:ok, {:error, error}}, _acc -> {:halt, {:error, error}}
      {:exit, reason}, _acc -> {:halt, {:error, reason}}
      err, _acc -> {:halt, err}
    end

    [
      &Getters.get_facilities/0,
      &Getters.get_vehicles/0,
      &Getters.get_weapons/0,
      &Getters.get_xp/0
    ]
    |> Task.async_stream(&get_data/1)
    |> Enum.reduce_while(%{}, reducer)
    |> case do
      {:error, _} = error_tuple -> error_tuple
      cache_map -> {:ok, cache_map}
    end
  end

  defp get_data(fun, attempt \\ 1, last_error \\ nil)

  defp get_data(_fun, @max_attempts, last_error) do
    Logger.error("Failed to fetch static data after #{@max_attempts} attempts, not retring.")
    {:error, last_error}
  end

  defp get_data(fun, attempt, _last_error) do
    case fun.() do
      {:ok, _pairs} = ok_tuple ->
        ok_tuple

      {:error, error} ->
        Logger.warning(
          "Failed to fetch static data with #{inspect(fun)} (attempt #{attempt}/#{@max_attempts}): #{inspect(error)}"
        )

        get_data(fun, attempt + 1, error)
    end
  end
end
