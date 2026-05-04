defmodule CAI.ESS.Client do
  @moduledoc """
  Consumes events from the ESS and injects them into the event stream.
  """
  @behaviour PS2.ESS

  use GenServer

  alias CAI.Event
  alias Ecto.Changeset

  require Logger

  @restart_ess_connection_after :timer.seconds(40)
  @supported_events [
    PS2.gain_experience(),
    PS2.death(),
    PS2.vehicle_destroy(),
    PS2.player_login(),
    PS2.player_logout(),
    PS2.player_facility_defend(),
    PS2.player_facility_capture(),
    PS2.battle_rank_up(),
    PS2.metagame_event(),
    PS2.continent_lock(),
    PS2.continent_unlock(),
    PS2.facility_control()
  ]
  @heartbeat PS2.server_health_update()

  @impl PS2.ESS
  def handle_event(%{"event_name" => @heartbeat}), do: heartbeat()

  # special case for random vehicles dying/despawning
  @impl PS2.ESS
  def handle_event(%{"event_name" => "VehicleDestroy", "character_id" => "0", "attacker_character_id" => "0"}) do
    :noop
  end

  @impl PS2.ESS
  def handle_event(%{"event_name" => event_name} = attrs) when event_name in @supported_events do
    case cast_event(attrs) do
      %Changeset{valid?: true} = event_cs -> CAI.emit_event(event_cs)
      changeset -> Logger.error("Couldn't cast ESS payload to event: #{inspect(changeset)}")
    end
  end

  @impl PS2.ESS
  def handle_event(_unknown), do: nil

  @doc """
  Casts the given attrs to an Event struct.
  """
  @spec cast_event(attrs :: map()) :: Changeset.t()
  def cast_event(attrs), do: Changeset.cast(%Event{}, %{"struct" => attrs}, [:struct])

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def heartbeat, do: GenServer.cast(__MODULE__, :ess_heartbeat)

  ### IMPL

  @impl GenServer
  def init(_) do
    timer_ref = Process.send_after(self(), :restart_ess_connection, @restart_ess_connection_after)
    {:ok, timer_ref}
  end

  @impl GenServer
  def handle_info(:restart_ess_connection, _timer_ref) do
    Logger.warning("No heartbeat received after #{@restart_ess_connection_after}ms, restarting socket")

    Supervisor.terminate_child(CAI.Supervisor, PS2.ESS)
    Supervisor.restart_child(CAI.Supervisor, PS2.ESS)
    {:noreply, Process.send_after(self(), :restart_ess_connection, @restart_ess_connection_after)}
  end

  @impl GenServer
  def handle_cast(:ess_heartbeat, timer_ref) do
    Process.cancel_timer(timer_ref)
    {:noreply, Process.send_after(self(), :restart_ess_connection, @restart_ess_connection_after)}
  end
end
