defmodule CAI.ESS.Client do
  @behaviour PS2.SocketClient

  alias CAI.ESS
  alias Phoenix.PubSub

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
  def handle_event({@heartbeat, payload}) do
    # handle socket reconnects here
  end

  @impl PS2.SocketClient
  def handle_event({event_name, payload}) do
    {:ok, event} = cast_event(event_name, payload)

    if is_map_key(event.changes, :character_id) do
      PubSub.broadcast(CAI.PubSub, "ess:#{event.changes.character_id}", event)
    end

    if is_map_key(event.changes, :attacker_character_id) do
      PubSub.broadcast(
        CAI.PubSub,
        "ess:#{event.changes.attacker_character_id}",
        event
      )
    end

    if is_map_key(event.changes, :other_id) do
      PubSub.broadcast(
        CAI.PubSub,
        "ess:#{event.changes.other_id}",
        event
      )
    end

    PubSub.broadcast(CAI.PubSub, "ess:#{event_name}", event)
  end

  alias Ecto.Changeset

  @doc """
  Casts the given payload to an event struct.
  """
  @spec cast_event(String.t(), map()) ::
          {:ok, struct()} | {:error, :unknown_event} | {:error, :bad_payload}
  def cast_event(event_name, payload) do
    with {:ok, module} <- Map.fetch(@event_map, event_name),
         %Changeset{} = changeset <- module.changeset(struct(module), payload) do
      {:ok, changeset}
    else
      false -> {:error, :unknown_event}
    end
  rescue
    ArgumentError -> {:error, :module_no_exist}
  end
end
