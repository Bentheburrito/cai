defmodule CAI.Characters do
  @moduledoc """
  The Characters context. Contains functions for interacting with the Census collections as well as locally stored
  sessions. Manages caches and retries automatically.
  """

  import CAI.Cachex
  import CAI.Guards, only: [is_character_id: 1]
  import Ecto.Query, warn: false
  import PS2.API.QueryBuilder, except: [field: 2]

  alias CAI.Characters.{Character, Outfit, Session}
  alias CAI.Repo
  alias Ecto.Changeset
  alias PS2.API, as: Census
  alias PS2.API.{Query, QueryResult}

  alias CAI.ESS.{
    Death,
    FacilityControl,
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
  @httpoison_timeout_ms 12 * 1000
  @default_census_attempts 3
  @query_base Query.new(collection: "character")
              |> resolve([
                "outfit(alias,id,name,leader_character_id,time_created_date)",
                "profile(profile_type_description)"
                # Leaving these out for now until needed later, and a shallow query is added
                # "stat_history(stat_name,all_time)",
                # "stat(stat_name,value_forever)",
                # "stat_by_faction(stat_name,value_forever_vs,value_forever_nc,value_forever_tr)"
              ])
              # |> join(
              #   Join.new(collection: "characters_weapon_stat")
              #   |> inject_at("weapon_stat")
              #   |> list(true)
              # )
              # |> join(
              #   Join.new(collection: "characters_weapon_stat_by_faction")
              #   |> inject_at("weapon_stat_by_faction")
              #   |> list(true)
              # )
              |> lang("en")

  @doc """
  Get a `Character` by their ID or name.

  The function first checks `characters()`, and falls back to a Census query on cache miss. The cache is updated
  on miss. Cache entries last for #{@cache_ttl_ms} milliseconds.

  Returns an ok tuple with the character struct on success. If the cache misses and Census returns no results,
  `:not_found` is returned. `:error` is returned in all other cases, and any Census errors are logged.

  TODO: return cached_at on cache hit, and remaining TTL?
  """
  @spec fetch(character_reference()) :: {:ok, Character.t()} | :not_found | :error
  def fetch(0), do: :not_found

  def fetch(name) when is_binary(name) do
    if String.length(name) < 3 do
      :error
    else
      name_lower = String.downcase(name)

      case Cachex.get(character_names(), name_lower) do
        {:ok, nil} ->
          query = term(@query_base, "name.first_lower", name_lower)
          fetch_by_query(query, &put_character_in_caches/1)

        {:ok, character_id} ->
          fetch(character_id)
      end
    end
  end

  def fetch(character_id) when is_character_id(character_id) do
    with {:ok, %Character{} = char} <- Cachex.get(characters(), character_id),
         {:ok, true} <- Cachex.put(character_names(), char.name_first_lower, character_id, @put_opts) do
      {:ok, char}
    else
      {:ok, nil} ->
        query = term(@query_base, "character_id", character_id)
        fetch_by_query(query, &put_character_in_caches/1)

      {:error, _} ->
        Logger.error("Could not access cache CAI.Cachex.characters()")
        :error
    end
  end

  def fetch(_non_character_id) do
    :error
  end

  @doc """
  Runs the given Census query, optionally transforming the result with the `map_to/1` parameter.

  Defaults to a maximum of #{@default_census_attempts} attempts. Returns the same as `fetch/1`.
  """
  @spec fetch_by_query(Query.t(), (any() -> any()), integer()) :: {:ok, Character.t()} | :not_found | :error
  def fetch_by_query(query, map_to \\ & &1, remaining_tries \\ @default_census_attempts)

  def fetch_by_query(_query, _map_to, remaining_tries) when remaining_tries == 0 do
    Logger.error("fetch_by_query: remaining_tries == 0, returning :error")
    :error
  end

  def fetch_by_query(query, map_to, remaining_tries) do
    case Census.query_one(query, CAI.sid()) do
      {:ok, %QueryResult{data: data, returned: returned}} when returned > 0 ->
        {:ok, map_to.(data)}

      {:ok, %QueryResult{returned: 0}} ->
        :not_found

      {:error, e} ->
        Logger.warning("fetch_by_query returned error (#{remaining_tries - 1} attempts remain): #{inspect(e)}")

        fetch_by_query(query, map_to, remaining_tries - 1)
    end
  end

  defp put_character_in_caches(data) do
    case %Character{} |> Character.changeset(data) |> Changeset.apply_action(:update) do
      {:ok, char} ->
        Cachex.put(characters(), char.character_id, char, @put_opts)
        Cachex.put(character_names(), char.name_first_lower, char.character_id, @put_opts)
        char

      {:error, %Changeset{} = changeset} ->
        Logger.error("Could not parse census character response into a Character struct: #{inspect(changeset.errors)}")

        :error
    end
  end

  defp put_outfit_in_cache(data) do
    case %Outfit{} |> Outfit.changeset(data) |> Changeset.apply_action(:update) do
      {:ok, outfit} ->
        Cachex.put(outfits(), outfit.outfit_id, outfit, ttl: round(@cache_ttl_ms / 2))
        outfit

      {:error, %Changeset{} = changeset} ->
        Logger.error("Could not parse census outfit response into an Outfit struct: #{inspect(changeset.errors)}")

        :error
    end
  end

  @doc """
  Get many characters.

  Similar to `fetch/1`, except it takes many character IDs, and returns a map. The map is keyed by the given character
  IDs, and the values will be the result of the query (see `fetch/1` return values).

  Non-character IDs in the given list are ignored.
  """
  @spec get_many(Enum.t()) :: %{character_id() => Character.t() | :not_found | :error}
  def get_many(character_ids) do
    # Step 1: Check the cache for these IDs, keeping track of IDs that are not in the cache.
    for id when is_character_id(id) <- character_ids, reduce: {[], %{}} do
      {uncached_ids, character_map} ->
        case Cachex.get(characters(), id) do
          {:ok, %Character{} = char} ->
            {uncached_ids, Map.put(character_map, char.character_id, char)}

          {:ok, nil} ->
            {[id | uncached_ids], Map.put(character_map, id, :not_found)}

          {:error, _} ->
            Logger.error("Could not access CAI.Cachex.characters()")
            {uncached_ids, character_map}
        end
    end
    # Step 2: If there are uncached_ids, query Census for them
    |> case do
      {[], character_map} ->
        character_map

      {uncached_ids, character_map} ->
        query = term(@query_base, "character_id", uncached_ids)
        new_character_map = get_many_by_query(query)
        # Must merge this way, since map2 key values override map1's
        Map.merge(character_map, new_character_map)
    end
  end

  @doc """
  Runs the given multi-character Census query, updating caches and parsing the result into a map of `Character` structs
  (see `get_many/1` above).

  Defaults to a maximum of #{@default_census_attempts} attempts. Returns the same as `get_many/1`.
  """
  @spec get_many_by_query(Query.t()) :: %{character_id() => Character.t() | :not_found | :error}
  def get_many_by_query(query, remaining_tries \\ @default_census_attempts)

  def get_many_by_query(_query, remaining_tries) when remaining_tries == 0 do
    Logger.error("remaining_tries == 0, returning %{}")
    %{}
  end

  def get_many_by_query(query, remaining_tries) do
    case Census.query(query, CAI.sid(), recv_timeout: @httpoison_timeout_ms) do
      {:ok, %QueryResult{data: data, returned: returned}} when returned > 0 ->
        Enum.reduce(data, %{}, &get_many_reducer/2)

      {:ok, %QueryResult{returned: 0}} ->
        %{}

      {:error, e} ->
        Logger.warning("get_many_by_query returned error (#{remaining_tries - 1} attempts remain): #{inspect(e)}")

        get_many_by_query(query, remaining_tries - 1)
    end
  end

  # Helper function that attempts to build a Character struct from a census response. Caches the Character upon success.
  defp get_many_reducer(character_params, character_map) do
    maybe_character =
      %Character{}
      |> Character.changeset(character_params)
      |> Changeset.apply_action(:update)

    case maybe_character do
      {:ok, %Character{character_id: character_id} = character} ->
        Cachex.put(characters(), character_id, character, @put_opts)
        Cachex.put(character_names(), character.name_first_lower, character_id, @put_opts)
        Map.put(character_map, character_id, character)

      {:error, changeset} ->
        Logger.error("Could not parse census character response into a Character struct: #{inspect(changeset.errors)}")

        character_map
    end
  end

  @doc """
  Get an outfit by its ID.
  """
  def fetch_outfit(outfit_id) when is_integer(outfit_id) do
    case Cachex.get(outfits(), outfit_id) do
      {:ok, %Outfit{} = outfit} ->
        {:ok, %Outfit{} = outfit}

      {:ok, nil} ->
        Query.new(collection: "outfit")
        |> term("outfit_id", outfit_id)
        |> lang("en")
        |> fetch_by_query(&put_outfit_in_cache/1)

      {:error, _} ->
        Logger.error("Could not access CAI.Cachex.outfits()")
        :error
    end
  end

  @doc """
  Get an ordered list of all events in a session.

  This function builds a session from the given character_id and login/logout timestamps, then iterates through its
  embedded events, returning a list of all events sorted in reverse-chronological (descending) order.

  If building a session fails (due to a changeset error), `{:error, changeset}` is returned instead.

  This function serves to be used in the event feed in session LiveViews.

  Since this is an expensive operation for longer game sessions, if `cache?` is `true` (which is the default), the
  event history and session may be cached for faster access later. This argument should really only be `false` when the
  session history could change (i.e. the character is online generating new events).

  TODO: cache results
  """
  @spec get_session_history(
          character_id() | Session.t(),
          login :: integer(),
          logout :: integer(),
          cache? :: boolean()
        ) :: [map()] | {:error, Ecto.Changeset.t()}
  def get_session_history(character_id_or_session, login, logout, cache? \\ true)

  def get_session_history(character_id, login, logout, _cache?) when is_character_id(character_id) do
    with {:ok, session} <- Session.build(character_id, login, logout) do
      get_session_history(session, login, logout)
    end
  end

  def get_session_history(%Session{} = session, login, logout, _cache?) do
    {world_id, zone_ids, facility_ids} =
      (Map.get(session, :player_facility_captures, []) ++ Map.get(session, :player_facility_defends, []))
      |> Enum.reduce({nil, MapSet.new(), MapSet.new()}, fn event, {_, zone_ids, facility_ids} ->
        {event.world_id, MapSet.put(zone_ids, event.zone_id), MapSet.put(facility_ids, event.facility_id)}
      end)

    [
      :battle_rank_ups,
      :deaths,
      :gain_experiences,
      :facility_control,
      :player_facility_captures,
      :player_facility_defends,
      :vehicle_destroys,
      :login,
      :logout
    ]
    |> Enum.reduce([], fn
      # special case for `embeds_one` fields (which aren't a list)
      field, event_list when field in [:login, :logout] ->
        case Map.fetch(session, field) do
          {:ok, nil} -> event_list
          {:ok, event} -> [event | event_list]
          _ -> event_list
        end

      # Instead of storing facility_control events on a Session, let's just make another query here
      :facility_control, event_list when not is_nil(world_id) ->
        FacilityControl
        |> where([fc], fc.timestamp >= ^login and fc.timestamp <= ^logout)
        |> where([fc], fc.world_id == ^world_id)
        |> where([fc], fc.zone_id in ^MapSet.to_list(zone_ids))
        |> where([fc], fc.facility_id in ^MapSet.to_list(facility_ids))
        |> Repo.all()
        |> Kernel.++(event_list)

      :facility_control, event_list ->
        event_list

      field, acc ->
        Enum.reduce(Map.fetch!(session, field), acc, fn event, event_list ->
          [event | event_list]
        end)
    end)
    |> Enum.sort_by(& &1.timestamp, :desc)
  end

  @default_session_count 10
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

  def get_session_boundaries(character_id, max_sessions) when is_character_id(character_id) do
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
