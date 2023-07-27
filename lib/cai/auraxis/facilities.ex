defmodule CAI.Auraxis.Facilities do
  @moduledoc """
  A GenServer that manages the CAI.Cachex.facilities() cache, updating it via the FacilityControl,
  PlayerFacilityCapture, and PlayerFacilityDefends events.
  """

  defmodule Entry do
    @moduledoc false

    defstruct latest_facility_control: :none
  end

  use GenServer

  import CAI.Cachex

  alias CAI.ESS.{FacilityControl, PlayerFacilityCapture, PlayerFacilityDefend}

  ### API ###

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  @doc """
  Gets the FacilityControl event associated with the given PlayerFacilityCapture or PlayerFacilityDefend event.

  Returns `{:ok, FacilityControl.t()}` if an entry exists, else `:none`.
  """
  def get_facility_control_for(%mod{} = event) when mod in [PlayerFacilityCapture, PlayerFacilityDefend] do
    %{world_id: world_id, zone_id: zone_id, facility_id: facility_id} = event

    case Cachex.get(facilities(), {world_id, zone_id, facility_id}) do
      {:ok, %Entry{latest_facility_control: fc_event}} -> {:ok, fc_event}
      {:ok, nil} -> :none
    end
  end

  ### IMPL ###

  @impl true
  def init(init_state) do
    Phoenix.PubSub.subscribe(CAI.PubSub, "ess:FacilityControl")

    {:ok, init_state}
  end

  @impl true
  def handle_info({:event, %FacilityControl{} = event}, state) do
    entry = %Entry{latest_facility_control: event}
    {:ok, true} = Cachex.put(facilities(), {event.world_id, event.zone_id, event.facility_id}, entry)
    {:noreply, state}
  end
end
