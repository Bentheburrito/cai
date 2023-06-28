defmodule CAI.ESS.Client do
  @behaviour PS2.SocketClient

  use GenServer

  alias CAI.ESS
  alias Ecto.Changeset
  alias Phoenix.PubSub

  require Logger

  @restart_socket_after 60 * 1000
  @event_map %{
    PS2.gain_experience() => ESS.GainExperience,
    PS2.death() => ESS.Death,
    PS2.vehicle_destroy() => ESS.VehicleDestroy,
    PS2.player_login() => ESS.PlayerLogin,
    PS2.player_logout() => ESS.PlayerLogout,
    PS2.player_facility_defend() => ESS.PlayerFacilityDefend,
    PS2.player_facility_capture() => ESS.PlayerFacilityCapture,
    PS2.battle_rank_up() => ESS.BattleRankUp,
    PS2.metagame_event() => ESS.MetagameEvent,
    PS2.continent_lock() => ESS.ContinentLock,
    PS2.continent_unlock() => ESS.ContinentUnlock
  }

  @heartbeat PS2.server_health_update()
  @impl PS2.SocketClient
  def handle_event({@heartbeat, _payload}) do
    heartbeat()
  end

  @supported_events Map.keys(@event_map)
  @impl PS2.SocketClient
  def handle_event({event_name, payload}) when event_name in @supported_events do
    case cast_event(event_name, payload) do
      {:ok, event} ->
        if is_map_key(event.changes, :character_id) do
          PubSub.broadcast(CAI.PubSub, "ess:#{event.changes.character_id}", {:event, event})
        end

        if is_map_key(event.changes, :attacker_character_id) do
          PubSub.broadcast(
            CAI.PubSub,
            "ess:#{event.changes.attacker_character_id}",
            {:event, event}
          )
        end

        if is_map_key(event.changes, :other_id) do
          PubSub.broadcast(CAI.PubSub, "ess:#{event.changes.other_id}", {:event, event})
        end

        PubSub.broadcast(CAI.PubSub, "ess:#{event_name}", {:event, event})

        CAI.Repo.insert!(event)

      {:error, reason} ->
        Logger.error("Couldn't handle event: #{reason}")
    end
  end

  @impl PS2.SocketClient
  def handle_event(_unknown) do
    # Logger.warning("Unknown ESS event: #{inspect(unknown)}")
    nil
  end

  @doc """
  Casts the given payload to an event struct.
  """
  @spec cast_event(String.t(), map()) ::
          {:ok, struct()} | {:error, :unknown_event} | {:error, :bad_payload}
  def cast_event(event_name, payload) do
    with {:ok, module} <- Map.fetch(@event_map, event_name),
         %Changeset{valid?: true} = changeset <- module.changeset(struct(module), payload) do
      {:ok, changeset}
    else
      %Changeset{valid?: false} -> {:error, :bad_payload}
      :error -> {:error, :unknown_event}
    end
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def heartbeat do
    GenServer.cast(__MODULE__, :socket_heartbeat)
  end

  ### IMPL

  @impl GenServer
  def init(_) do
    timer_ref = Process.send_after(self(), :restart_socket, @restart_socket_after)
    {:ok, timer_ref}
  end

  @impl GenServer
  def handle_info(:restart_socket, _timer_ref) do
    Supervisor.restart_child(CAI.Supervisor, PS2.Socket)
    {:noreply, Process.send_after(self(), :restart_socket, @restart_socket_after)}
  end

  @impl GenServer
  def handle_cast(:socket_heartbeat, timer_ref) do
    Process.cancel_timer(timer_ref)
    {:noreply, Process.send_after(self(), :restart_socket, @restart_socket_after)}
  end
end
