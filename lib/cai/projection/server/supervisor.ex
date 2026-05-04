defmodule CAI.Projection.Server.Supervisor do
  @moduledoc """
  Dynamically creates and revives `RadioBeam.Room.Server`s under its
  supervision.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 15)
  end

  def start_server(server_key) do
    DynamicSupervisor.start_child(__MODULE__, {CAI.Projection.Server, server_key})
  end
end
