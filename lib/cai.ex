defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def sid, do: System.get_env("SERVICE_ID")

  @json_cache_path "./cache"

  @vehicles CAI.Scripts.load_static_file(@json_cache_path <> "/vehicles.json")
  def vehicles, do: @vehicles

  @xp CAI.Scripts.load_static_file(@json_cache_path <> "/xp.json")
  def xp, do: @xp

  @assist_xp Stream.filter(@xp, fn {_id, %{"description" => desc}} ->
               desc
               |> String.downcase()
               |> String.contains?("assist")
             end)
             |> Enum.map(fn {id, _} -> id end)
  defguard is_assist_xp(id) when id in @assist_xp

  @gunner_assist_xp Stream.filter(@xp, fn {_id, %{"description" => desc}} ->
                      desc = String.downcase(desc)

                      String.contains?(desc, "kill by") and
                        not String.contains?(desc, ["hive xp", "squad member"])
                    end)
                    |> Enum.map(fn {id, _} -> id end)
  defguard is_gunner_assist_xp(id) when id in @gunner_assist_xp

  @revive_xp_ids [7, 53]
  def revive_xp_ids, do: @revive_xp_ids
  defguard is_revive_xp(id) when id in @revive_xp_ids

  @weapons CAI.Scripts.load_static_file(@json_cache_path <> "/weapons.json")
  def weapons, do: @weapons

  @facilities CAI.Scripts.load_static_file(@json_cache_path <> "/facilities.json")
  def facilities, do: @facilities

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
