defmodule CAI.Cachex.StaticDataWarmer do
  @moduledoc """
  Reads static data from endpoints every #{CAI.Cachex.static_data_interval_hours()} hours, dumping the result at
  #{CAI.Cachex.dump_path()}.
  """
  use Cachex.Warmer

  require Logger

  import CAI.Cachex

  alias CAI.Cachex.StaticDataWarmer.Getters

  @impl true
  def interval, do: :timer.hours(static_data_interval_hours())

  @max_attempts 3
  @doc """
  Tries to load the dump at #{dump_path()} into CAI.Cachex.static_data(). If it does not exist, we will query the
  GitHub/Census endpoints to populate the cache, and then dump it.

  This fn will retry querying for static data #{@max_attempts} times before failing.
  """
  @impl true
  def execute(_) do
    case Cachex.Disk.read(dump_path()) do
      {:ok, pairs} ->
        Logger.info("Successfully loaded static data from #{dump_path()}")
        {:ok, pairs}

      error ->
        Logger.info("Unable to load dumpfile at #{dump_path()}: #{inspect(error)} attempting to fetch...")

        case query_static_data() do
          {:ok, pairs} ->
            IO.inspect(is_list(pairs), label: "pairs is list?")
            IO.inspect(is_map(pairs), label: "pairs is map?")
            Cachex.Disk.write(pairs, dump_path())
            Logger.info("Successfully fetched and dumped static data!")
            {:ok, pairs}

          {:error, error} ->
            Logger.error("Failed to query_static_data: #{inspect(error)}")
        end
    end
  end

  defp query_static_data() do
    # Outer ok tuple is the result of the task from Task.async_stream, the inner ok tuple is from the Getters fxns
    reducer = fn
      {:ok, {:ok, entries}}, acc -> {:cont, IO.inspect(Map.merge(acc, entries), label: "cont")}
      {:ok, {:error, error}}, _acc -> {:halt, IO.inspect({:error, error}, label: "err query")}
      {:exit, reason}, _acc -> {:halt, IO.inspect({:error, reason}, label: "err task stream")}
      err, _acc -> {:halt, IO.inspect(err, label: "OH WTF")}
    end

    [
      &Getters.get_facilities/0,
      &Getters.get_vehicles/0,
      &Getters.get_weapons/0,
      &Getters.get_xp/0
    ]
    |> Task.async_stream(&get_data/1)
    |> IO.inspect(label: "stream")
    |> Enum.reduce_while(%{}, reducer)
    |> case do
      {:error, _} = error_tuple -> error_tuple
      map -> {:ok, Map.to_list(map)}
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
