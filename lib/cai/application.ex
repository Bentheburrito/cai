defmodule CAI.Application do
  @moduledoc false

  use Application

  import CAI.Cachex
  import Cachex.Spec

  alias CAI.Characters

  @impl true
  def start(_type, _args) do
    subscriptions = CAI.ess_subscriptions()

    ess_opts = [
      subscriptions: subscriptions,
      clients: [CAI.ESS.Client],
      service_id: CAI.sid(),
      endpoint: "push.nanite-systems.net/streaming"
    ]

    static_data_opts = [
      name: static_data(),
      warmers: [
        warmer(module: CAI.Cachex.StaticDataWarmer, state: [])
      ]
    ]

    census_transformers = %{
      "character" => [
        &Characters.cast_characters/1,
        &Characters.put_characters_in_caches/1,
        &Characters.unwrap_if_one/1
      ],
      "outfit" => [&Characters.cast_outfits/1, &Characters.put_outfits_in_cache/1, &Characters.unwrap_if_one/1]
    }

    children = [
      # Start the Telemetry supervisor
      CAIWeb.Telemetry,
      # Start the Ecto repository
      CAI.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: CAI.PubSub},
      # Start the Endpoint (http/https)
      CAIWeb.Endpoint,
      # Start our Cachex caches
      Supervisor.child_spec({Cachex, name: character_names()}, id: character_names()),
      Supervisor.child_spec({Cachex, name: characters()}, id: characters()),
      Supervisor.child_spec({Cachex, name: facilities()}, id: facilities()),
      Supervisor.child_spec({Cachex, name: outfits()}, id: outfits()),
      Supervisor.child_spec({Cachex, static_data_opts}, id: static_data()),
      # Start the Census gateway TaskSupervisor
      {Task.Supervisor, name: CAI.Census.TaskSupervisor},
      # Start the Census gateway gen_statem
      {CAI.Census, transformers: census_transformers},
      # Start the ESS Client
      CAI.ESS.Client,
      # Start the ESS Socket
      {PS2.Socket, ess_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CAI.Supervisor, max_seconds: 15_000]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CAIWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
