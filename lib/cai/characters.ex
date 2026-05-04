defmodule CAI.Characters do
  @moduledoc """
  The Characters context. Contains functions for interacting with the Census collections as well as locally stored
  sessions. Manages caches and retries automatically.
  """

  import CAI.Cachex
  import CAI.Guards, only: [is_character_id: 1]
  import Ecto.Query, warn: false
  import PS2.API.QueryBuilder, except: [field: 2, limit: 2]

  alias CAI.Census
  alias CAI.Characters.{Character, Outfit}
  alias Ecto.Changeset
  alias PS2.API.Query

  require Logger

  @type character_id :: integer()
  @type character_name :: String.t()
  @type character_reference :: character_name | character_id
  @type character_fetch_result :: {:ok, Character.t()} | :not_found | {:error, :timeout | :bad_character_ref | map()}
  @type character_async_result :: character_fetch_result() | {:fetching, Query.t()}

  @cache_ttl_ms 12 * 60 * 60 * 1000
  @put_opts [ttl: @cache_ttl_ms]
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

  The function first checks the `characters()` cache, and falls back to a Census query on cache miss. The cache is
  updated on miss. Cache entries last for #{@cache_ttl_ms} milliseconds.

  Returns an ok tuple with the character struct on success. If the cache misses and Census returns no results,
  `:not_found` is returned. `:error` is returned in all other cases, and any Census errors are logged.

  TODO: return cached_at on cache hit, and remaining TTL?
  """
  @spec fetch(character_reference()) :: character_fetch_result()
  def fetch(character_reference) do
    do_fetch(character_reference, &Census.fetch/1)
  end

  @doc """
  Similar to `fetch/1`, but immediately returns `{:fetching, Query.t()}` and later sends the caller a message
  with the result of the query.

  The message takes the form of `{:fetch, character_reference, query_result}`, where
  `character_reference` is the referenced passed to this function, and `query_result`
  is one of `{:ok, Character.t()} | :not_found | :error`
  """
  @spec fetch_async(character_reference()) :: character_async_result()
  def fetch_async(character_reference) do
    do_fetch(character_reference, fn query ->
      :ok = Census.fetch_async(query)
      {:fetching, query}
    end)
  end

  defp do_fetch(0, _fallback_fn), do: :not_found

  defp do_fetch(name, fallback_fn) when is_binary(name) do
    if String.length(name) < 3 do
      :error
    else
      name_lower = String.downcase(name)

      case Cachex.get(character_names(), name_lower) do
        {:ok, nil} ->
          @query_base
          |> term("name.first_lower", name_lower)
          |> fallback_fn.()

        {:ok, character_id} ->
          fetch(character_id)
      end
    end
  end

  defp do_fetch(character_id, fallback_fn) when is_character_id(character_id) do
    with {:ok, %Character{} = char} <- Cachex.get(characters(), character_id),
         {:ok, true} <- Cachex.put(character_names(), char.name_first_lower, character_id, @put_opts) do
      {:ok, char}
    else
      {:ok, nil} ->
        @query_base
        |> term("character_id", character_id)
        |> fallback_fn.()

      {:error, _} ->
        Logger.error("Could not access cache CAI.Cachex.characters()")
        :error
    end
  end

  defp do_fetch(_non_character_id, _fallback_fn) do
    {:error, :bad_character_ref}
  end

  # (TODO): make behaviour for these transformers
  def cast_characters(data) do
    for params <- data do
      %Character{}
      |> Character.changeset(params)
      |> Changeset.apply_action(:update)
      |> case do
        {:ok, character} ->
          character

        {:error, %Changeset{} = changeset} ->
          Logger.error(
            "Could not parse census character response into a Character struct: #{inspect(changeset.errors)}"
          )

          changeset
      end
    end
  end

  def put_characters_in_caches(characters) do
    for %Character{} = character <- characters do
      Cachex.put(characters(), character.character_id, character, @put_opts)
      Cachex.put(character_names(), character.name_first_lower, character.character_id, @put_opts)
      character
    end
  end

  def unwrap_if_one([character]), do: character
  def unwrap_if_one(non_one_list), do: non_one_list

  # def put_characters_in_caches(not_ok_tuple), do: not_ok_tuple

  def cast_outfits(data) do
    for params <- data do
      %Outfit{}
      |> Outfit.changeset(params)
      |> Changeset.apply_action(:update)
      |> case do
        {:ok, outfit} ->
          outfit

        {:error, %Changeset{} = changeset} ->
          Logger.error("Could not parse census outfit response into an Outfit struct: #{inspect(changeset.errors)}")

          changeset
      end
    end
  end

  def put_outfits_in_cache(outfits) do
    for %Outfit{} = outfit <- outfits do
      Cachex.put(outfits(), outfit.outfit_id, outfit, ttl: round(@cache_ttl_ms / 2))
      outfit
    end
  end

  @doc """
  Get many characters.

  Similar to `fetch/1`, except it takes many character IDs, and returns a map. The map is keyed by the given character
  IDs, and the values will be the result of the query (see `fetch/1` return values).

  Non-character IDs in the given list are ignored.
  """
  @spec get_many(Enum.t(character_id())) :: %{character_id() => Character.t() | :not_found | :error}
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
        {:ok, characters} =
          @query_base
          |> term("character_id", uncached_ids)
          |> Census.fetch()

        new_character_map =
          characters
          |> List.wrap()
          |> Map.new(&{&1.character_id, &1})

        # Must merge this way, since map2 key values override map1's
        Map.merge(character_map, new_character_map)
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
        |> Census.fetch()

      {:error, _} ->
        Logger.error("Could not access CAI.Cachex.outfits()")
        :error
    end
  end

  def online?(character_id) when is_character_id(character_id) do
    case CAI.game_sessions(character_id) do
      %{sessions: [%{status: :in_progress} | _]} -> true
      _else -> false
    end
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

      {:error, error} ->
        Logger.error("get_session_boundaries/2 failed to fetch character, #{character_name}: #{inspect(error)}")
        :error
    end
  end
end
