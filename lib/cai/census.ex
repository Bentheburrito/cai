defmodule CAI.Census do
  @moduledoc """
  Dispatcher and ratelimiter for Census queries.
  """

  alias CAI.Census.TaskSupervisor
  alias PS2.API
  alias PS2.API.{Query, QueryResult}

  require Logger

  @behaviour :gen_statem

  # `:pending` is a map that looks like %{Query.t() => [list_of_PIDs]}}
  # `:failed` is a similar map, but the values are the number of retries for that particular query.
  # e.g. %{Query.t() => number_of_retries}
  # `:transformers` is a map of collection names to a list of transformers.
  # e.g. %{"character" => [&cast_to_char_struct/1, &put_in_caches/1]}
  defstruct pending: %{},
            failed: %{},
            fail_count: 0,
            transformers: %{}

  ### CONSTANTS

  @closed_timeout_ms 10_000
  @fail_count_threshold 3
  @httpoison_timeout_ms 6 * 1000
  @max_query_retries 5
  # @max_queries_in_flight 3
  @slowed_period_ms 1_500

  ### API

  @spec fetch_async(Query.t()) :: :ok
  def fetch_async(query) do
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

  def opened(:cast, {:fetch, from, query}, %__MODULE__{} = state), do: {:keep_state, handle_request(state, from, query)}
  def opened(:info, {:fetch_complete, query, {:ok, _} = result}, state), do: handle_result(state, query, result)
  def opened(:info, {:fetch_complete, query, :not_found}, state), do: handle_result(state, query, :not_found)

  def opened(:info, {:fetch_complete, query, :timeout}, %__MODULE__{} = state) do
    fail_count = state.fail_count + 1
    state = %__MODULE__{state | fail_count: fail_count}
    Logger.info("opened, got timeout")

    # if we just ran into a bunch of failures in a row, let's slow things down
    if fail_count >= @fail_count_threshold do
      Logger.info("fail_count met #{@fail_count_threshold}, transitioning to slowed")

      {:next_state, :slowed, retry_if_able(state, query, :timeout)}
    else
      fly(query, Map.get(state.transformers, query.collection, []))

      {:keep_state, state}
    end
  end

  # errored query result
  def opened(:info, {:fetch_complete, query, {:error, error}}, %__MODULE__{} = state) do
    Logger.info("opened, got error, transitioning to slowed")

    fail_count = state.fail_count + 1

    state = %__MODULE__{state | fail_count: fail_count}

    # in the case of an error that's not a timeout, let's immediately transition to :slowed
    {:next_state, :slowed, retry_if_able(state, query, error)}
  end

  # anything else doesn't make sense to receive in :opened state
  def opened(event_type, event_content, %__MODULE__{} = state) do
    Logger.warning("Got #{inspect(event_type)} event in opened state: #{inspect(event_content)}")
    {:keep_state, state}
  end

  def slowed(:cast, {:fetch, from, query}, %__MODULE__{} = state) do
    state = handle_request(state, from, query)

    if state.fail_count == 0 do
      Logger.info("handling request in :slowed, but fail_count == 0, so transitioning to :opened")
      {:next_state, :opened, state}
    else
      Logger.info("handling request in :slowed, transitioning to :closed for #{@slowed_period_ms}ms")
      {:next_state, :closed, state, [{:state_timeout, @slowed_period_ms, :slowed}]}
    end
  end

  # successful query
  def slowed(:info, {:fetch_complete, query, {:ok, _} = result}, %__MODULE__{} = state) do
    {_, state} = handle_result(state, query, result)

    if state.fail_count == 0 do
      Logger.info("transitioning from slowed -> opened (reached 0 fail count)")
      {:next_state, :opened, state}
    else
      {:keep_state, state}
    end
  end

  # successful (but resource not found) query result
  def slowed(:info, {:fetch_complete, query, :not_found}, %__MODULE__{} = state) do
    {_, state} = handle_result(state, query, :not_found)

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
    if fail_count >= @fail_count_threshold + round(@fail_count_threshold / 2) do
      Logger.info(
        "fail_count exceeded #{@fail_count_threshold + round(@fail_count_threshold / 2)} == @fail_count_threshold + round(@fail_count_threshold / 2) in :slowed, going to :closed"
      )

      {:next_state, :closed, retry_if_able(state, query, :timeout),
       [{:state_timeout, @closed_timeout_ms, {:fail_count, 1}}]}
    else
      {:keep_state, retry_if_able(state, query, :timeout)}
    end
  end

  # errored query result
  def slowed(:info, {:fetch_complete, query, {:error, error}}, %__MODULE__{} = state) do
    # in the case of an error that's not a timeout, let's immediately transition to :closed
    {:next_state, :closed, retry_if_able(state, query, error), [{:state_timeout, @closed_timeout_ms, :slowed}]}
  end

  # anything else doesn't make sense to receive in :slowed state
  def slowed(event_type, event_content, %__MODULE__{} = state) do
    Logger.warning("Got #{inspect(event_type)} event in slowed state: #{inspect(event_content)}")
    {:keep_state, state}
  end

  def closed(:state_timeout, {:fail_count, n}, state), do: {:next_state, :slowed, %__MODULE__{state | fail_count: n}}
  def closed(:state_timeout, old_state, %__MODULE__{} = state), do: {:next_state, old_state, state}
  def closed(:cast, {:fetch, _from, _query}, state), do: {:keep_state, state, [:postpone]}
  def closed(:info, {:fetch_complete, query, {:ok, _} = result}, state), do: handle_result(state, query, result)
  def closed(:info, {:fetch_complete, query, :not_found}, state), do: handle_result(state, query, :not_found)

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

  # if this request is a :retry, the requesting PIDs are already in :pending, so there's nothing to do
  defp handle_request(%__MODULE__{} = state, :retry, query) do
    fly(query, Map.get(state.transformers, query.collection, []))

    state
  end

  # flies a request query (unless it's already been requested). Adds the requester to the :pending MapSet
  defp handle_request(%__MODULE__{} = state, from, query) do
    unless is_map_key(state.pending, query) do
      fly(query, Map.get(state.transformers, query.collection, []))
    end

    %__MODULE__{state | pending: Map.update(state.pending, query, MapSet.new([from]), &MapSet.put(&1, from))}
    # cond do
    #   map_size(state.pending) > @max_queries_in_flight ->
    #     {:next_state, :closed, %__MODULE__{state | open_into: current_state},
    #       [{:state_timeout, @closed_timeout_ms, :slowed}]}
    # end
  end

  # re-cast a failed request if it has not exceeded its max retries
  defp retry_if_able(%__MODULE__{} = state, query, error) do
    case Map.get(state.failed, query, 0) do
      num_retries when num_retries < @max_query_retries ->
        :gen_statem.cast(__MODULE__, {:fetch, :retry, query})

        %__MODULE__{state | failed: Map.put(state.failed, query, num_retries + 1)}

      _max_retries_exceeded ->
        Logger.info("max retries exceeded for query with error #{inspect(error)}: #{inspect(query)}")

        state
        |> handle_result(query, {:error, error})
        |> elem(1)
    end
  end

  defp fly(query, transformers) do
    statem = self()

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      query
      |> API.query(CAI.sid(), recv_timeout: @httpoison_timeout_ms)
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
    Logger.info("Census request resulted in a timeout")

    :timeout
  end

  defp from_query_result({:error, error}) do
    Logger.error("Census request resulted in an error: #{inspect(error)}")

    {:error, error}
  end

  defp handle_result(state, query, result) do
    {pids, pending} = Map.pop(state.pending, query, [])
    failed = Map.delete(state.failed, query)

    state = %__MODULE__{state | pending: pending, failed: failed}

    Logger.info(
      "forwarding #{inspect((is_tuple(result) && elem(result, 0)) || result)} to requesters: #{inspect(pids)}"
    )

    for pid <- pids, do: send(pid, {:fetch, query, result})

    state =
      if match?({:error, _}, result) do
        state
      else
        fail_count = max(0, state.fail_count - 1)
        %__MODULE__{state | fail_count: fail_count}
      end

    {:keep_state, state}
  end
end
