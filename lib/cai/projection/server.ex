defmodule CAI.Projection.Server do
  @moduledoc """
  A GenServer that applies events to a Projection
  """
  use GenServer, restart: :transient, shutdown: :timer.seconds(10)

  alias CAI.Event
  alias CAI.Projection.Server.Supervisor
  alias CAI.Projection
  alias CAI.Repo
  alias CAI.PubSub

  require Logger

  @registry CAI.Projection.Registry
  @inactivity_timeout_ms :timer.minutes(5)

  ### API ###

  def start_link({projector, key}), do: GenServer.start_link(__MODULE__, {projector, key}, name: via({projector, key}))

  defp via({projector, key}), do: {:via, Registry, {@registry, {projector, key}}}

  def apply_event(projector, key, %Event{} = event) when is_atom(projector) do
    with {:ok, pid} <- lookup_server({projector, key}), do: GenServer.cast(pid, {:handle_event, event})
  end

  defp lookup_server(server_key) do
    case Registry.lookup(@registry, server_key) do
      [{pid, _}] -> {:ok, pid}
      _ -> with {:error, {:already_started, pid}} <- Supervisor.start_server(server_key), do: {:ok, pid}
    end
  end

  def alive?(projector, key) do
    case Registry.lookup(@registry, {projector, key}) do
      [{_pid, _}] -> true
      _else -> false
    end
  end

  ### IMPL ###

  @impl GenServer
  def init({projector, key}), do: {:ok, {projector, key}, {:continue, :load_or_init_projection}}

  @impl GenServer
  def handle_continue(:load_or_init_projection, {projector, key}) do
    projection =
      case Repo.get_by(Projection, projector: to_string(projector), key: to_string(key)) do
        nil ->
          %Projection{}
          |> Ecto.Changeset.cast(
            %{projector: to_string(projector), key: to_string(key), state: projector.init(key)},
            ~w|projector key state|a
          )
          |> Repo.insert!()

        %Projection{} = projection ->
          projection
      end

    with [_ | _] = topics <- projector.pubsub_keys(projection.state) do
      for topic <- topics, do: PubSub.subscribe(topic)
    end

    noreply(projection)
  end

  @impl GenServer
  def handle_cast({:handle_event, event}, %Projection{state: %projector{}} = projection) do
    new_projection_state = projector.handle_event(projection.state, event.struct)

    projection =
      projection
      |> Ecto.Changeset.cast(
        %{state: new_projection_state, projected_up_to_index: event.index},
        ~w|state projected_up_to_index|a
      )
      |> Repo.insert_or_update!()

    PubSub.broadcast(PubSub.character_event(projection.key), {:event_handled, event})

    noreply(projection)
  end

  @impl GenServer
  def handle_info(:timeout, %Projection{} = projection), do: {:stop, :normal, projection}

  # this is for world events that don't have a character ID we can use to fetch
  # via the registry.
  @impl GenServer
  def handle_info({:apply_event, %Event{} = event}, %Projection{} = projection) do
    handle_cast({:handle_event, event}, projection)
  end

  defp noreply(state), do: {:noreply, state, @inactivity_timeout_ms}

  ### the below didn't work because EventHandler only sends a subset of
  # relevant events based on projector.keys, but then the projection server is
  # unaware of that, so it just re-fetches all the irrelevant events from the DB
  # when it received a relevant event :/ did this logic in EventHandler's init/1
  # instead

  # @impl GenServer
  # def handle_cast({:handle_event, event}, %Projection{state: %projector{}} = projection) do
  #   events_to_apply =
  #     case get_missing_events(projection, event.index) do
  #       [] -> [event]
  #       events when is_list(events) -> Stream.concat(events, [event])
  #     end
  #
  #   new_projection_state =
  #     Enum.reduce(events_to_apply, projection.state, fn event, state ->
  #       projector.handle_event(state, event.struct)
  #     end)
  #
  #   projection =
  #     projection
  #     |> Ecto.Changeset.cast(
  #       %{state: new_projection_state, projected_up_to_index: event.index},
  #       ~w|state projected_up_to_index|a
  #     )
  #     |> Repo.insert_or_update!()
  #
  #   PubSub.broadcast(CAI.PubSub, "projection_updated:#{projector}:#{projection.key}", {:event_handled, event})
  #
  #   {:noreply, projection}
  # end
  #
  # defp get_missing_events(projection, event_index) when projection.projected_up_to_index == event_index - 1, do: []
  #
  # # we're going to make a lossy assumption that if this projection hasn't seen
  # # events before, it's because there weren't any relevant events before now.
  # # This might not always be true in reality, but we will need a way to
  # # determine that better, instead of doing what we were before, which is just
  # # fetch all the events from the beginning of time regardless of relevancy to
  # # current projection and run them through.
  # #
  # # a better way to determine relevancy is to implement event streams (e.g.
  # # storing an additional event log per projection key). That's going to take a
  # # lot more storage though.
  # defp get_missing_events(projection, _event_index) when is_nil(projection.projected_up_to_index) do
  #   Logger.debug("skipping backfill for #{projection.key} as it is brand new.")
  #   []
  # end
  #
  # defp get_missing_events(projection, event_index) when projection.projected_up_to_index < event_index - 1 do
  #   dbg("getting more events (projected up to #{projection.projected_up_to_index} but we're handling #{event_index})")
  #
  #   Event
  #   |> where([e], e.index > coalesce(^projection.projected_up_to_index, -1) and e.index < ^event_index)
  #   |> order_by([e], asc: e.index)
  #   |> Repo.all()
  # end
end
