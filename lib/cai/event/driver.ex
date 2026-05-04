defmodule CAI.Event.Cache do
  use GenServer

  import Ecto.Query

  alias CAI.Event

  require Logger

  @cache_max 10_000
  @cleanup_interval :timer.seconds(30)

  def put(%Event{} = event) do
    true = :ets.insert(__MODULE__, {event.index, event})
    :ok
  end

  def all(starting_at_index \\ 1) do
    if :ets.first(__MODULE__) > starting_at_index do
      CAI.Repo.all(from e in Event, where: e.index >= ^starting_at_index, order_by: [asc: e.index])
    else
      :ets.select(__MODULE__, [{{:"$1", :"$2"}, [{:>=, :"$1", starting_at_index}], [:"$2"]}])
    end
  end

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  ### IMPL ###

  @impl GenServer
  def init(_) do
    tid =
      :ets.new(__MODULE__, [:named_table, :public, :ordered_set, write_concurrency: :auto, decentralized_counters: true])

    cleanup_timer = queue_cleanup()

    {:ok, {tid, cleanup_timer}}
  end

  @impl GenServer
  def handle_info(:cleanup, {tid, _timer_ref}) do
    first..last//_ = indices = :ets.first(tid)..:ets.last(tid)

    if Range.size(indices) > @cache_max do
      delete_all_before = last - @cache_max
      num_deleted = :ets.select_delete(tid, [{{:"$1", :_}, [{:<, :"$1", delete_all_before}], [:"$_"]}])
      Logger.info("Cache cleanup: removed #{num_deleted} (indices #{first}..#{delete_all_before})")
      {tid, queue_cleanup()}
    else
      {tid, queue_cleanup()}
    end
  end

  defp queue_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
