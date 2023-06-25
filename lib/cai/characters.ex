defmodule CAI.Characters do
  @moduledoc """
  The Characters context.
  """

  import Ecto.Query, warn: false
  import PS2.API.QueryBuilder, except: [field: 2]

  alias Ecto.Changeset
  alias CAI.Repo
  alias CAI.Characters.{Character, Session}
  alias CAI.ESS
  alias PS2.API, as: Census
  alias PS2.API.{Join, Query, QueryResult}

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
  @spec get_character(character_reference()) :: {:ok, Character.t()} | :not_found | :error
  def get_character(0), do: :not_found

  def get_character(name) when is_binary(name) do
    name_lower = String.downcase(name)

    case Cachex.get(:character_name_map, name_lower) do
      {:ok, nil} ->
        query = term(@query_base, "name.first_lower", name_lower)
        query_character(query)

      {:ok, character_id} ->
        get_character(character_id)
    end
  end

  def get_character(character_id) when is_integer(character_id) do
    with {:ok, %Character{} = char} <- Cachex.get(:character_cache, character_id),
         {:ok, true} <-
           Cachex.put(:character_cache, char.name_first_lower, character_id, @put_opts) do
      {:ok, char}
    else
      {:ok, nil} ->
        query = term(@query_base, "character_id", character_id)
        query_character(query)

      {:error, _} ->
        Logger.error("Could not access :character_cache")
        :error
    end
  end

  @doc """
  Runs the given character Census query, updating caches and parsing the result into a `Character` struct.

  Defaults to a maximum of #{@default_census_attempts} attempts. Returns the same as `get_character/1`.
  """
  @spec query_character(Query.t(), integer()) :: {:ok, Character.t()} | :not_found | :error
  def query_character(query, remaining_tries \\ @default_census_attempts)
  def query_character(_query, remaining_tries) when remaining_tries == 0, do: :error

  def query_character(query, remaining_tries) do
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

        query_character(query, remaining_tries - 1)
    end
  end

  @default_session_count 10
  @doc """
  TODO: Not finished implementing yet.

  Get a character's first `max_sessions` sessions.

  Sessions are fetched in reverse chronological order (latest -> oldest). `max_sessions` defaults to
  #{@default_session_count}.

  TODO: Optimize this function. We need a better strategy to distinguish sessions based on the total collection of ESS
  events. Might need a mapping table/cache managed at the application layer, which the nostrum consumer uses to classify
  events under a session as they're received, rather than later when querying here.
  """
  @spec get_sessions(character_reference(), max_sessions :: integer()) ::
          {:ok, [Session.t()]} | :not_found | :error
  def get_sessions(character_id, max_sessions \\ @default_session_count)

  def get_sessions(character_name, max_sessions) when is_binary(character_name) do
    case get_character(character_name) do
      {:ok, %Character{character_id: character_id}} ->
        get_sessions(character_id, max_sessions)

      :not_found ->
        :not_found

      :error ->
        Logger.error("get_sessions/2 failed to fetch character, #{character_name}")
        :error
    end
  end

  def get_sessions(character_id, max_sessions) when is_integer(character_id) do
    where_clause = [character_id: character_id]

    attack_where_clause =
      dynamic(
        [e],
        field(e, :character_id) == ^character_id or
          field(e, :attacker_character_id) == ^character_id
      )

    revive_xp_ids = CAI.revive_xp_ids()

    # Considers GE revive events where other_id is this character (i.e., this character was revived by someone else)
    ge_where_clause =
      dynamic(
        [e],
        field(e, :character_id) == ^character_id or
          (field(e, :other_id) == ^character_id and
             field(e, :experience_id) in ^revive_xp_ids)
      )

    all_gain_xp = Repo.all(build_event_query(ESS.GainExperience, ge_where_clause))
    all_deaths = Repo.all(build_event_query(ESS.Death, attack_where_clause))
    all_vehicle_destroys = Repo.all(build_event_query(ESS.VehicleDestroy, attack_where_clause))
    all_facility_defs = Repo.all(build_event_query(ESS.PlayerFacilityDefend, where_clause))
    all_facility_caps = Repo.all(build_event_query(ESS.PlayerFacilityCapture, where_clause))
    logins = Repo.all(build_event_query(ESS.PlayerLogin, where_clause))
    logouts = Repo.all(build_event_query(ESS.PlayerLogout, where_clause))
    all_br_ups = Repo.all(build_event_query(ESS.BattleRankUp, where_clause))

    # Keep the bigger lists to the right of ++ ...still very slow, would be very nice to find a way to do this at the DB
    # level. See TODO above for optimizing?
    events = all_deaths ++ all_gain_xp
    events = all_vehicle_destroys ++ events
    events = all_facility_defs ++ events
    events = all_facility_caps ++ events
    events = logins ++ events
    events = logouts ++ events
    events = all_br_ups ++ events
    events = Enum.sort_by(events, & &1.timestamp, :desc)

    # from here, need to split events into distinct sessions...
  end

  defp ge_where_clause(character_id, login_timestamp) do
    revive_xp_ids = CAI.revive_xp_ids()

    dynamic(
      [e],
      (field(e, :character_id) == ^character_id and
         field(e, :timestamp) >= ^login_timestamp) or
        (field(e, :other_id) == ^character_id and
           field(e, :experience_id) in ^revive_xp_ids and
           field(e, :timestamp) >= ^login_timestamp)
    )
  end

  defp get_logout_timestamp(character_id, login_timestamp) do
    query =
      from(event in ESS.PlayerLogout,
        select: min(event.timestamp),
        where: event.character_id == ^character_id and event.timestamp > ^login_timestamp
      )

    case Repo.one(query) do
      nil -> :current_session
      logout_timestamp -> logout_timestamp
    end
  end

  defp build_event_query(event_module, conditional) do
    from(event in event_module, where: ^conditional, order_by: [desc: :timestamp])
  end

  defp build_where_clause(clause, logout_timestamp) do
    case logout_timestamp do
      :current_session ->
        clause

      logout_timestamp ->
        dynamic([e], field(e, :timestamp) <= ^logout_timestamp and ^clause)
    end
  end
end
