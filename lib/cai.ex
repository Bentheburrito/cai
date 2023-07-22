defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  require CAI

  import Bitwise

  def sid, do: System.get_env("SERVICE_ID")

  @json_cache_path "./cache"

  @vehicles CAI.Scripts.load_static_file(@json_cache_path <> "/vehicles.json")
  def vehicles, do: @vehicles

  @xp CAI.Scripts.load_static_file(@json_cache_path <> "/xp.json")
  def xp, do: @xp

  kill_xp_filter = fn {_id, %{"description" => desc}} ->
    desc = String.downcase(desc)
    (String.contains?(desc, "kill") or String.contains?(desc, "headshot")) and not String.contains?(desc, "assist")
  end

  @kill_xp @xp |> Stream.filter(kill_xp_filter) |> Enum.map(fn {id, _} -> id end)
  defguard is_kill_xp(id) when id in @kill_xp

  assist_xp_filter = fn {_id, %{"description" => desc}} ->
    desc
    |> String.downcase()
    |> String.contains?("assist")
  end

  @assist_xp @xp |> Stream.filter(assist_xp_filter) |> Enum.map(fn {id, _} -> id end)
  defguard is_assist_xp(id) when id in @assist_xp

  gunner_assist_xp_filter = fn {_id, %{"description" => desc}} ->
    desc = String.downcase(desc)

    String.contains?(desc, "kill by") and
      not String.contains?(desc, ["hive xp", "squad member"])
  end

  @gunner_assist_xp @xp
                    |> Stream.filter(gunner_assist_xp_filter)
                    |> Enum.map(fn {id, _} -> id end)
  defguard is_gunner_assist_xp(id) when id in @gunner_assist_xp

  @revive_xp_ids [7, 53]
  def revive_xp_ids, do: @revive_xp_ids
  defguard is_revive_xp(id) when id in @revive_xp_ids

  @doc """
  Get the image icon for the given experience_id and team/faction ID
  """
  @spec xp_icon(experience_id :: integer(), team_id :: integer()) :: {:ok, image_url :: String.t()} | :noop
  def xp_icon(id, team_id)
  # kill streak
  def xp_icon(8, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/92995.png")}
  # domination
  def xp_icon(10, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/11874.png")}
  # revenge
  def xp_icon(11, _team_id), do: {:ok, "/images/11874_red.png"}
  # nemesis
  def xp_icon(32, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/14229.png")}
  # spot kill
  # def xp_icon(36, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/84758.png")}
  # spot kill alt 1
  def xp_icon(36, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/14692.png")}
  # spot kill alts 2
  # def xp_icon(36, 1), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/12634.png")}
  # def xp_icon(36, 2), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/12628.png")}
  # def xp_icon(36, 3), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/12631.png")}
  # def xp_icon(36, team_id) when team_id in [0, 4], do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/12637.png")}
  # headshot
  def xp_icon(37, _team_id), do: {:ok, "/images/77759_cropped.png"}
  # headshot alt 1
  # def xp_icon(37, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/12483.png")}
  # headshot alts 2
  # def xp_icon(37, 1), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/11467.png")}
  # def xp_icon(37, 2), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/11464.png")}
  # def xp_icon(37, 3), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/11461.png")}
  # stop kill streak
  def xp_icon(38, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/2609.png")}
  # priority
  def xp_icon(278, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/14985.png")}
  # high priority
  def xp_icon(279, _team_id), do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/14985.png")}
  # bounty kill bonus
  def xp_icon(593, _team_id), do: {:ok, "/images/92995_red_cropped.png"}

  def xp_icon(_, _), do: :noop

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
        image: "/images/NSO.png"
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
        image: "/images/NSO.png"
      }
    }

  @doc """
  Character IDs are always odd.

  https://discord.com/channels/251073753759481856/451032574538547201/1089955112216170496
  """
  defguard is_character_id(id) when is_integer(id) and (1 &&& id) == 1

  @doc """
  NPC IDs are always even.

  https://discord.com/channels/251073753759481856/451032574538547201/1089955112216170496
  """
  defguard is_npc_id(id) when is_integer(id) and (1 &&& id) == 0

  def character_id?(id), do: is_character_id(id)
  def npc_id?(id), do: is_npc_id(id)

  def ess_subscriptions do
    [
      events: [
        PS2.gain_experience(),
        PS2.death(),
        PS2.vehicle_destroy(),
        PS2.player_login(),
        PS2.player_logout(),
        PS2.player_facility_capture(),
        PS2.player_facility_defend(),
        PS2.battle_rank_up(),
        PS2.metagame_event(),
        PS2.continent_unlock(),
        PS2.continent_lock(),
        PS2.facility_control()
      ],
      worlds: ["all"],
      characters: ["all"]
    ]
  end

  def please_report_msg do
    "If the issue persists, please consider creating an issue on GitHub (link in footer at the bottom of the page!)"
  end
end
