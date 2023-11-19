defmodule CAI.Characters.Fetcher do
  @moduledoc """
  Dispatcher and ratelimiter for Census queries.

  ##### thoughts

  ## what am I actually trying to solve here?
  - we retry 3 times before abandoning a request. During bursts of timeouts/service_unavailables,
    these retries don't matter - they will all fail eventually and just waste time retrying.
  - so, let's start simple - circuit-breaker state machine. We get X timeouts, buffer queries for Y seconds, then
    reintroduce them 1:1. It'll be very possible to continuously stockpile requests in the queue/buffer, so an
    internal timeout mechanism will likely be needed later.

  let's also start moving away from Characters context. It's already 500+ lines. This module
  is going to be responsible for servicing %Character{} requests, and maintaining the cache for those requests. That's
  it.

  ## How the fetcher will work

  1. requests sent to gen_statem from `fetch` fn, which checks cache, returns struct on hit.
  2. on miss, sends statem a message with the char ID or name and the calling PID.
  3. statem will handle the message depending on its current state:
  3a. if :opened, request immediately takes flight to the Census
  3b. if :slowed, request goes to the buffer
  3c. if :closed, request goes to the buffer
  4. if the query does not take flight after a timeout, it's discarded and a message is sent to the caller to notify it
  5. once the query takes flight and returns, the result is sent to the caller, the cache, and may affect change the
     state in the following ways:
  5a. if :opened and result was success, no state change
  5b. if :opened and result was timeout, inc error count
  5c. if :opened and result was error/service_unavailable, state change to :slowed
  5d. if :slowed and result was success, inc success count
  5e. if :slowed and result was timeout, inc error count
  5f. if :slowed and result was error/service_unavailable, state change to :closed
  5g. if :closed and result was success, inc success count
  5h. if :closed and result was timeout, no state change
  5i. if :closed and result was error/service_unavailable, no state change

  !!! REQUESTS NEED METADATA TO INDICATE WHAT ATTEMPT #.

  """

  import CAI.Cachex
  import CAI.Guards, only: [is_character_id: 1]

  alias CAI.Characters.Fetcher.TaskSupervisor
  alias CAI.Characters.Character
  alias Ecto.Changeset
  alias PS2.API, as: Census
  alias PS2.API.{Query, QueryResult}

  require Logger

  @behaviour :gen_statem

  # awaiting is a map, where the keys are `Query.t()`s, and the values are a list of the requesting PIDs.
  @enforce_keys [:self]
  defstruct awaiting: %{}, self: nil

  @type query_result :: {:ok, Character.t()} | :not_found | :error

  ### CONSTANTS
  @cache_ttl_ms 12 * 60 * 60 * 1000
  @put_opts [ttl: @cache_ttl_ms]

  @take_off_period_ms 300
  @into %{
    :character => {CAI.Characters.Character, CAI.Cachex.characters()}
  }

  ### API

  @spec fetch(Query.t()) :: query_result()
  def fetch(%Query{} = query) do
  end

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    :gen_statem.start_link({:local, name}, __MODULE__, [], opts)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  ### IMPL

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(_) do
    {:ok, :opened, %__MODULE__{self: self()}}
  end

  # off({call,From}, push, Data) ->
  #   %% Go to 'on', increment count and reply
  #   %% that the resulting status is 'on'
  #   {next_state,on,Data+1,[{reply,From,on}]};

  # off(EventType, EventContent, Data) ->
  #     handle_event(EventType, EventContent, Data).

  def opened({:call, from}, {:fetch, query}, %__MODULE__{} = state) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      query
      |> Census.query_one(CAI.sid())
      |> from_query_result()
      |> maybe_put_caches()
      |> case do
        :error ->


        reply ->
          send(from, reply)
      end
    end)
  end

  # on({call,From}, push, Data) ->
  #     %% Go to 'off' and reply that the resulting status is 'off'
  #     {next_state,off,Data,[{reply,From,off}]};
  # on(EventType, EventContent, Data) ->
  #     handle_event(EventType, EventContent, Data).

  # %% Handle events common to all states
  # handle_event({call,From}, get_count, Data) ->
  #     %% Reply with the current count
  #     {keep_state,Data,[{reply,From,Data}]};
  # handle_event(_, _, Data) ->
  #     %% Ignore all other events
  #     {keep_state,Data}.

  defp from_query_result({:ok, %QueryResult{returned: 0}}), do: :not_found

  defp from_query_result({:ok, %QueryResult{data: data, returned: returned}}) when returned > 0 do
    case %Character{} |> Character.changeset(data) |> Changeset.apply_action(:update) do
      {:ok, character} -> character

      {:error, %Changeset{} = changeset} = error ->
        Logger.error("Could not parse census character response into a Character struct: #{inspect(changeset.errors)}")

        :error
    end
  end

  defp from_query_result({:error, error}) do
    Logger.info(__MODULE__, "Census request resulted in an error for this query #{inspect(query)}: #{inspect(e)}")

    :error
  end

  defp maybe_put_caches(%Character{} = character) do
    Cachex.put(characters(), character.character_id, character, @put_opts)
    Cachex.put(character_names(), character.name_first_lower, character.character_id, @put_opts)
    character
  end

  defp maybe_put_caches(not_a_character), do: not_a_character
end
