defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def sid, do: System.get_env("SERVICE_ID")

  def revive_xp_ids, do: [7, 53]
end
