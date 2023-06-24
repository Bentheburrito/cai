defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def sid, do: System.get_env("SERVICE_ID")

  def revive_xp_ids, do: [7, 53]

  def factions,
    do: %{
      0 => %{
        name: "No Faction",
        alias: "NS",
        color: 0x575757,
        image: "/images/faction/NSO.png"
      },
      1 => %{
        name: "Vanu Sovereignty",
        alias: "VS",
        color: 0xB035F2,
        image: "https://bit.ly/2RCsHXs"
      },
      2 => %{
        name: "New Conglomerate",
        alias: "NC",
        color: 0x2A94F7,
        image: "https://bit.ly/2AOZJJB"
      },
      3 => %{
        name: "Terran Republic",
        alias: "TR",
        color: 0xE52D2D,
        image: "https://bit.ly/2Mm6wij"
      },
      4 => %{
        name: "Nanite Systems",
        alias: "NSO",
        color: 0xE5E5E5,
        image: "/images/faction/NSO.png"
      }
    }
end
