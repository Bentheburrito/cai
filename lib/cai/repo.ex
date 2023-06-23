defmodule CAI.Repo do
  use Ecto.Repo,
    otp_app: :cai,
    adapter: Ecto.Adapters.Postgres
end
