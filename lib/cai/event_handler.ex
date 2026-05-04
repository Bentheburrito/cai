defmodule CAI.EventHandler do
  @moduledoc """
  A GenServer that applies events to relevant projections
  """
  use GenServer

  import Ecto.Query

  alias CAI.Character.GameSessionList
  alias CAI.Event
  alias CAI.Projection
  alias CAI.PubSub

  require Logger

  # @enforce_keys ~w|projection key|a
  # defstruct projection: nil, key: nil, projected_to: 0

  @projectors [GameSessionList]

  ### API ###

  def start_link(init_arg), do: GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)

  def queue_event(%Event{} = event), do: GenServer.cast(__MODULE__, {:handle_event, event})

  ### IMPL ###

  @impl GenServer
  def init(_) do
    # next_index = Event |> last(:index) |> select([e], e.index) |> CAI.Repo.one() || 0

    # note: we purposefully block init/1 with these queries - don't want
    # writers (ESS.Client) to start inserting events while we determine what
    # the last one we saw is.
    last_seen_index =
      Projection
      |> where([p], p.projector in ^Enum.map(@projectors, &to_string/1))
      |> last(:projected_up_to_index)
      |> select([p], p.projected_up_to_index)
      |> CAI.Repo.one() || 0

    latest_event_index =
      Event
      |> where([e], e.index > ^last_seen_index)
      |> order_by([e], asc: e.index)
      |> CAI.Repo.all()
      |> Enum.reduce(last_seen_index, fn event, _ ->
        queue_event(event)
        event.index
      end)

    {:ok, %{next_index: latest_event_index + 1, queue: :ordsets.new()}}
  end

  @impl GenServer
  def handle_cast({:handle_event, %{index: next_index} = event}, %{next_index: next_index} = state) do
    for projector <- @projectors, projection_key <- projector.keys(event.struct) do
      Projection.Server.apply_event(projector, projection_key, event)
    end

    with %mod{} when mod in [ContinentUnlock, ContinentLock, FacilityControl, MetagameEvent] <- event.struct do
      PubSub.broadcast(PubSub.world_event(event.struct.world_id), {:apply_event, event})
    end

    :ordsets.map(&queue_event/1, state.queue)

    {:noreply, %{next_index: next_index + 1, queue: :ordsets.new()}}
  end

  @impl GenServer
  def handle_cast({:handle_event, %{index: index} = event}, %{next_index: next_index} = state)
      when index > next_index do
    {:noreply, update_in(state.queue, &:ordsets.add_element(event, &1))}
  end

  @impl GenServer
  def handle_cast({:handle_event, %{index: index}}, %{next_index: next_index} = state) when index < next_index do
    # discard this old event - projections will backfill
    {:noreply, state}
  end
end
