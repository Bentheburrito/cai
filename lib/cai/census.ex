defmodule CAI.Census do
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

  alias CAI.Census.TaskSupervisor
  alias PS2.API
  alias PS2.API.{Query, QueryResult}

  require Logger

  @behaviour :gen_statem

  # pending is a map that looks like %{Query.t() => [list_of_PIDs]}}
  # failed is a similar map, but the values are the number of retries for that particular query.
  # e.g. %{Query.t() => number_of_retries}
  # transformers is a map of collection names to a list of transformers.
  # e.g. %{"character" => [&cast_to_char_struct/1, &put_in_caches/1]}
  defstruct pending: %{},
            failed: %{},
            fail_count: 0,
            fetch_queue: :queue.new(),
            pop_buffer_timer_ref: nil,
            transformers: %{}

  # @type query_result :: {:ok, Character.t()} | :not_found | :error

  ### CONSTANTS

  @closed_timeout_ms 6_000
  @fail_count_threshold 3
  @httpoison_timeout_ms 12 * 1000
  @max_query_retries 2
  @slowed_period_ms 1_000

  ### API

  # In the future, instead of taking a query, may consider storing  {collection, param, value} and constructing the
  # query when needed, and distributing results based on the requested resource trio, instead of per-query (e.g. in some
  # [albeit rare] cases, 2 different queries could partially be requesting the same resource, and so requesting the same
  # resource twice could be avoided). Additionally, instead of taking a `from`, could use pubsub to distribute results?
  @spec fetch_async(Query.t()) :: :ok
  def fetch_async(query) do
    # param = if param == :prefix_collection, do: "#{collection}_id", else: param

    # :gen_statem.cast(__MODULE__, {:fetch, self(), collection, {reference_name, reference}, query})
    # :gen_statem.cast(__MODULE__, {:fetch, collection, param, value})
    :gen_statem.cast(__MODULE__, {:fetch, self(), query})
  end

  def fetch(query) do
    :ok = fetch_async(query)

    receive do
      {:fetch, ^query, result} -> result
    end
  end

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    transformers = Keyword.get(opts, :transformers, [])
    :gen_statem.start_link({:local, name}, __MODULE__, transformers, opts)
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
  def init(transformers) do
    {:ok, :opened, %__MODULE__{transformers: transformers}}
  end

  # query request
  def opened(:cast, {:fetch, from, query}, %__MODULE__{} = state) do
    unless is_map_key(state.pending, query) do
      fly(query, Map.get(state.transformers, query.collection, []))
    end

    {:keep_state, put_pending(state, from, query)}
  end

  # successful query result
  def opened(:info, {:fetch_complete, query, {:ok, _} = result}, state), do: forward_result(state, query, result)
  def opened(:info, {:fetch_complete, query, :not_found}, state), do: forward_result(state, query, :not_found)

  # timeout query result
  def opened(:info, {:fetch_complete, query, :timeout}, %__MODULE__{} = state) do
    fail_count = state.fail_count + 1
    state = %__MODULE__{state | fail_count: fail_count}

    # if we just ran into a bunch of failures in a row, let's slow things down
    if fail_count >= @fail_count_threshold do
      Logger.info("fail_count met #{@fail_count_threshold}, transitioning to slowed")

      fail_count = state.fail_count + 1
      timer_ref = Process.send_after(self(), :pop_buffer, @slowed_period_ms)
      state = %__MODULE__{state | fail_count: fail_count, pop_buffer_timer_ref: timer_ref}

      {:next_state, :slowed, retry_if_able(state, query, :timeout)}
    else
      Logger.info("opened, got timeout")
      fly(query, Map.get(state.transformers, query.collection, []))

      {:keep_state, state}
    end
  end

  # errored query result
  def opened(:info, {:fetch_complete, query, {:error, error}}, %__MODULE__{} = state) do
    Logger.info("opened, got error, transitioning to slowed")

    fail_count = state.fail_count + 1
    timer_ref = Process.send_after(self(), :pop_buffer, @slowed_period_ms)

    state = %__MODULE__{state | fail_count: fail_count, pop_buffer_timer_ref: timer_ref}

    # in the case of an error that's not a timeout, let's immediately transition to :slowed
    {:next_state, :slowed, retry_if_able(state, query, error)}
  end

  # if we transition :slowed -> :opened and there are queries in the buffer, we want to continue to send those out
  # while in :opened
  def opened(:info, :pop_buffer, %__MODULE__{} = state), do: slowed(:info, :pop_buffer, state)

  # anything else doesn't make sense to receive in :opened state
  def opened(event_type, event_content, %__MODULE__{} = state) do
    Logger.warning("Got #{inspect(event_type)} event in opened state: #{inspect(event_content)}")
    {:keep_state, state}
  end

  def slowed(:cast, {:fetch, from, query} = request, %__MODULE__{} = state) do
    # if there is no timer ref, this is the first fetch req since transitioning to :slowed
    if is_nil(state.pop_buffer_timer_ref) do
      Logger.info("in slowed w/ no timer, flying and starting a timer...")

      timer_ref = Process.send_after(self(), :pop_buffer, @slowed_period_ms)
      state = %__MODULE__{state | pop_buffer_timer_ref: timer_ref}

      unless is_map_key(state.pending, query) do
        fly(query, Map.get(state.transformers, query.collection, []))
      end

      {:keep_state, put_pending(state, from, query)}
    else
      state = %__MODULE__{state | fetch_queue: :queue.in(request, state.fetch_queue)}

      {:keep_state, put_pending(state, from, query)}
    end
  end

  # successful query
  def slowed(:info, {:fetch_complete, query, {:ok, _} = result}, %__MODULE__{} = state) do
    {_, state} = forward_result(state, query, result)

    if state.fail_count == 0 do
      Logger.info("transitioning from slowed -> opened (reached 0 fail count)")
      {:next_state, :opened, state}
    else
      {:keep_state, state}
    end
  end

  # successful (but resource not found) query result
  def slowed(:info, {:fetch_complete, query, :not_found}, %__MODULE__{} = state) do
    {_, state} = forward_result(state, query, :not_found)

    if state.fail_count == 0 do
      Logger.info("transitioning from slowed -> opened (reached 0 fail count)")
      {:next_state, :opened, state}
    else
      {:keep_state, state}
    end
  end

  # timeout query result
  def slowed(:info, {:fetch_complete, query, :timeout}, %__MODULE__{} = state) do
    fail_count = state.fail_count + 1
    state = %__MODULE__{state | fail_count: fail_count}

    # if things are still bad after slowing down, stop requests for a while by transitioning to :closed
    if fail_count >= @fail_count_threshold do
      Process.cancel_timer(state.pop_buffer_timer_ref)
      state = %__MODULE__{state | pop_buffer_timer_ref: nil}

      {:next_state, :closed, retry_if_able(state, query, :timeout), [{:state_timeout, @closed_timeout_ms, :slowed}]}
    else
      {:keep_state, retry_if_able(state, query, :timeout)}
    end
  end

  # errored query result
  def slowed(:info, {:fetch_complete, query, {:error, error}}, %__MODULE__{} = state) do
    Process.cancel_timer(state.pop_buffer_timer_ref)
    state = %__MODULE__{state | pop_buffer_timer_ref: nil}

    # in the case of an error that's not a timeout, let's immediately transition to :closed
    {:next_state, :closed, retry_if_able(state, query, error), [{:state_timeout, @closed_timeout_ms, :slowed}]}
  end

  def slowed(:info, :pop_buffer, %__MODULE__{} = state) do
    case :queue.out(state.fetch_queue) do
      {{:value, {:fetch, _from, query}}, queue} ->
        Logger.info("getting next queued query in :slowed, flying next query")
        timer_ref = Process.send_after(self(), :pop_buffer, @slowed_period_ms)
        state = %__MODULE__{state | pop_buffer_timer_ref: timer_ref, fetch_queue: queue}

        fly(query, Map.get(state.transformers, query.collection, []))

        {:keep_state, state}

      {:empty, _queue} ->
        Logger.info("getting next queued query in :slowed, but it was empty")
        {:keep_state, %__MODULE__{state | pop_buffer_timer_ref: nil}}
    end
  end

  # anything else doesn't make sense to receive in :slowed state
  def slowed(event_type, event_content, %__MODULE__{} = state) do
    Logger.warning("Got #{inspect(event_type)} event in slowed state: #{inspect(event_content)}")
    {:keep_state, state}
  end

  # we've been :closed for a while, let's transition back to :slowed and try some queries again
  def closed(:state_timeout, _old_state, %__MODULE__{} = state) do
    # for now, let's be a bit optimistic and set fail_count = 1. This means it will
    # take 1 successful :slowed query to get back into :opened.
    {:next_state, :slowed, %__MODULE__{state | fail_count: 1}}
  end

  # postpone fetch requests when :closed
  def closed(:cast, {:fetch, _from, _query}, %__MODULE__{} = state) do
    {:keep_state, state, [:postpone]}
  end

  # successful query result
  def closed(:info, {:fetch_complete, query, {:ok, _} = result}, state), do: forward_result(state, query, result)
  def closed(:info, {:fetch_complete, query, :not_found}, state), do: forward_result(state, query, :not_found)

  # timeout query result
  def closed(:info, {:fetch_complete, query, :timeout}, %__MODULE__{} = state) do
    {:keep_state, retry_if_able(state, query, :timeout)}
  end

  # errored query result
  def closed(:info, {:fetch_complete, query, {:error, error}}, %__MODULE__{} = state) do
    {:keep_state, retry_if_able(state, query, error)}
  end

  # anything else doesn't make sense to receive in :closed state
  def closed(event_type, event_content, %__MODULE__{} = state) do
    Logger.warning("Got #{inspect(event_type)} event in closed state: #{inspect(event_content)}")
    {:keep_state, state}
  end

  ### HELPERS

  # append the given `from` PID to the list under key `query` in the :pending map
  defp put_pending(%__MODULE__{} = state, from, query) do
    %__MODULE__{state | pending: Map.update(state.pending, query, MapSet.new([from]), &MapSet.put(&1, from))}
  end

  # pop an element from the :pending map, also clearing any entry in :failed
  defp pop_pending(%__MODULE__{} = state, query) do
    {pids, pending} = Map.pop(state.pending, query, [])
    failed = Map.delete(state.failed, query)

    {pids, %__MODULE__{state | pending: pending, failed: failed}}
  end

  # puts a failed request's query in the :fetch_queue if it has not exceeded its max retries
  defp retry_if_able(%__MODULE__{} = state, query, error) do
    case Map.get(state.failed, query, 0) do
      num_retries when num_retries < @max_query_retries ->
        fetch_queue = :queue.in({:fetch, :pid_irrelevant, query}, state.fetch_queue)
        %__MODULE__{state | failed: Map.put(state.failed, query, num_retries + 1), fetch_queue: fetch_queue}

      _max_retries_exceeded ->
        Logger.info("max retries exceeded for query with error #{inspect(error)}: #{inspect(query)}")

        state
        |> forward_result(query, {:error, error})
        |> elem(1)
    end
  end

  defp fly(query, transformers) do
    statem = self()

    Logger.info(
      "query for resource #{inspect(query.collection)}/#{inspect(query.params["character_id"] || query.params["name.first_lower"])} about to take flight"
    )

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      query
      |> API.query(CAI.sid())
      |> from_query_result()
      |> case do
        {:ok, data} ->
          {:ok, Enum.reduce(transformers, data, & &1.(&2))}

        not_found_or_error ->
          not_found_or_error
      end
      |> then(&send(statem, {:fetch_complete, query, &1}))
    end)
  end

  defp from_query_result({:ok, %QueryResult{returned: 0}}), do: :not_found

  defp from_query_result({:ok, %QueryResult{data: data, returned: returned}}) when returned > 0 do
    {:ok, data}
  end

  defp from_query_result({:error, %HTTPoison.Error{reason: :timeout}}) do
    :timeout
  end

  defp from_query_result({:error, error}) do
    Logger.error("Census request resulted in an error: #{inspect(error)}")

    {:error, error}
  end

  defp forward_result(state, query, result) do
    {pids, state} = pop_pending(state, query)

    Logger.info(
      "forwarding #{inspect((is_tuple(result) && elem(result, 0)) || result)} to requesters: #{inspect(pids)}"
    )

    for pid <- pids, do: send(pid, {:fetch, query, result})

    fail_count = max(0, state.fail_count - 1)

    {:keep_state, %__MODULE__{state | fail_count: fail_count, failed: Map.delete(state.failed, query)}}
  end
end
