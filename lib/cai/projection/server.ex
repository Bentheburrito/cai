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
end
