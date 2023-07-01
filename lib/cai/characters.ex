defmodule CAI.Characters do
  @moduledoc """
  The Characters context. Contains functions for interacting with the Census collections as well as locally stored
  sessions. Manages caches and retries automatically.
  """

  import Ecto.Query, warn: false
  import PS2.API.QueryBuilder, except: [field: 2]

  alias Ecto.Changeset
  alias CAI.Repo
  alias CAI.Characters.{Character, Session}
  alias PS2.API, as: Census
  alias PS2.API.{Join, Query, QueryResult}

  alias CAI.ESS.{
    Death,
    GainExperience,
    PlayerFacilityCapture,
    PlayerFacilityDefend,
    PlayerLogin,
    PlayerLogout,
    VehicleDestroy
  }

  require Logger

  @type character_id :: integer()
  @type character_name :: String.t()
  @type character_reference :: character_name | character_id

  @cache_ttl_ms 12 * 60 * 60 * 1000
  @put_opts [ttl: @cache_ttl_ms]
  @httpoison_timeout_ms 10 * 1000
  @default_census_attempts 3
  @query_base Query.new(collection: "character")
              |> resolve([
                "outfit(alias,id,name,leader_character_id,time_created_date)",
                "profile(profile_type_description)",
                "stat_history(stat_name,all_time)",
                "stat(stat_name,value_forever)",
                "stat_by_faction(stat_name,value_forever_vs,value_forever_nc,value_forever_tr)"
              ])
              |> join(
                Join.new(collection: "characters_weapon_stat")
                |> inject_at("weapon_stat")
                |> list(true)
              )
              |> join(
                Join.new(collection: "characters_weapon_stat_by_faction")
                |> inject_at("weapon_stat_by_faction")
                |> list(true)
              )
              |> lang("en")

  @doc """
  Get a `Character` by their ID or name.

  The function first checks `:character_cache`, and falls back to a Census query on cache miss. The cache is updated
  on miss. Cache entries last for #{@cache_ttl_ms} milliseconds.

  Returns an ok tuple with the character struct on success. If the cache misses and Census returns no results,
  `:not_found` is returned. `:error` is returned in all other cases, and any Census errors are logged.

  TODO: return cached_at on cache hit, and remaining TTL?
  """
  @spec fetch(character_reference()) :: {:ok, Character.t()} | :not_found | :error
  def fetch(0), do: :not_found

  def fetch(name) when is_binary(name) do
    name_lower = String.downcase(name)

    case Cachex.get(:character_name_map, name_lower) do
      {:ok, nil} ->
        query = term(@query_base, "name.first_lower", name_lower)
        fetch_by_query(query)

      {:ok, character_id} ->
        fetch(character_id)
    end
  end

  def fetch(character_id) when is_integer(character_id) do
    with {:ok, %Character{} = char} <- Cachex.get(:character_cache, character_id),
         {:ok, true} <-
           Cachex.put(:character_cache, char.name_first_lower, character_id, @put_opts) do
      {:ok, char}
    else
      {:ok, nil} ->
        query = term(@query_base, "character_id", character_id)
        fetch_by_query(query)

      {:error, _} ->
        Logger.error("Could not access :character_cache")
        :error
    end
  end

  @doc """
  Runs the given character Census query, updating caches and parsing the result into a `Character` struct.

  Defaults to a maximum of #{@default_census_attempts} attempts. Returns the same as `fetch/1`.
  """
  @spec fetch_by_query(Query.t(), integer()) :: {:ok, Character.t()} | :not_found | :error
  def fetch_by_query(query, remaining_tries \\ @default_census_attempts)
  def fetch_by_query(_query, remaining_tries) when remaining_tries == 0, do: :error

  def fetch_by_query(query, remaining_tries) do
    with {:ok, %QueryResult{data: data, returned: returned}} when returned > 0 <-
           Census.query_one(query, CAI.sid()),
         {:ok, char} <-
           %Character{} |> Character.changeset(data) |> Changeset.apply_action(:update) do
      Cachex.put(:character_cache, char.character_id, char, @put_opts)
      Cachex.put(:character_name_map, char.name_first_lower, char.character_id, @put_opts)
      {:ok, char}
    else
      {:ok, %QueryResult{returned: 0}} ->
        :not_found

      {:error, %Changeset{} = changeset} ->
        Logger.error(
          "Could not parse census character response into a Character struct: #{inspect(changeset.errors)}"
        )

        :error

      {:error, e} ->
        Logger.warning(
          "CharacterCache query returned error (#{remaining_tries - 1} attempts remain): #{inspect(e)}"
        )

        fetch_by_query(query, remaining_tries - 1)
    end
  end

  @default_session_count 10
  @doc """
  TODO: Not finished implementing yet.

  Get a character's first `max_sessions` sessions.

  Sessions are fetched in reverse chronological order (latest -> oldest). `max_sessions` defaults to
  #{@default_session_count}.
  """
  @spec get_sessions(character_reference(), max_sessions :: integer()) ::
          {:ok, [Session.t()]} | :not_found | :error
  def get_sessions(character_ref, max_sessions) do
    with {:ok, character_id, timestamp_pairs} <-
           get_session_boundaries(character_ref, max_sessions) do
      sessions =
        Enum.map(timestamp_pairs, fn {login, logout} ->
          {:ok, session} = Session.build(character_id, login, logout)
          session
        end)

      {:ok, sessions}
    end
  end

  @spec get_session_boundaries(character_reference(), max_sessions :: integer()) ::
          {:ok, character_id, [{integer(), integer()}]} | :not_found | :error
  def get_session_boundaries(character_id, max_sessions \\ @default_session_count)

  def get_session_boundaries(character_name, max_sessions) when is_binary(character_name) do
    case fetch(character_name) do
      {:ok, %Character{character_id: character_id}} ->
        get_session_boundaries(character_id, max_sessions)

      :not_found ->
        :not_found

      :error ->
        Logger.error("get_session_boundaries/2 failed to fetch character, #{character_name}")
        :error
    end
  end

  def get_session_boundaries(character_id, max_sessions) when is_integer(character_id) do
    case list_all_timestamps(character_id) do
      [_first_pair | _rest] = timestamp_event_type_pairs ->
        get_session_boundaries(character_id, timestamp_event_type_pairs, max_sessions)

      # no previous sessions 😱
      [] ->
        {:ok, character_id, []}
    end
  end

  defp get_session_boundaries(
         character_id,
         [first_pair | timestamp_event_type_pairs],
         max_sessions
       ) do
    %{timestamp: first_pair_timestamp} = first_pair
    init_acc = {first_pair, first_pair_timestamp, length(timestamp_event_type_pairs), []}

    {_, _, _, timestamp_pairs} =
      timestamp_event_type_pairs
      |> Stream.with_index(1)
      |> Enum.reduce_while(init_acc, &session_reducer(&1, &2, max_sessions))

    {:ok, character_id, Enum.reverse(timestamp_pairs)}
  end

  # Note: we are reducing in descending order, so "last_" values are actually chronologically later than `event`.
  defp session_reducer({event, index}, {last_event, end_ts, end_index, acc}, max_sessions) do
    %{timestamp: ts, type: t} = event
    %{timestamp: last_ts, type: last_t} = last_event

    cond do
      index == end_index ->
        {:halt, {event, ts, end_index, [{last_ts, end_ts} | acc]}}

      session_boundary?(t, last_t, ts, last_ts) ->
        action = if length(acc) + 1 >= max_sessions, do: :halt, else: :cont
        {action, {event, ts, end_index, [{last_ts, end_ts} | acc]}}

      :else ->
        {:cont, {event, end_ts, end_index, acc}}
    end
  end

  @session_boundary_secs 30 * 60
  defp session_boundary?(_, "login", _, _), do: true
  defp session_boundary?("logout", _, _, _), do: true
  defp session_boundary?(_, _, ts1, ts2), do: ts2 - ts1 > @session_boundary_secs

  defp list_all_timestamps(character_id) do
    init_query =
      from(ge in GainExperience,
        select: %{timestamp: ge.timestamp, type: "ge"},
        where: ge.character_id == ^character_id
      )

    [
      {Death, "death"},
      {VehicleDestroy, "vd"},
      {PlayerFacilityCapture, "pfc"},
      {PlayerFacilityDefend, "pfd"},
      {PlayerLogin, "login"},
      {PlayerLogout, "logout"}
    ]
    |> Enum.reduce(init_query, fn {mod, type}, query ->
      to_union =
        from(e in mod,
          select: %{timestamp: e.timestamp, type: ^type},
          where: e.character_id == ^character_id
        )

      union_all(query, ^to_union)
    end)
    |> subquery()
    |> order_by(desc: :timestamp)
    |> Repo.all()
  end
end
