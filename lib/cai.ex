defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  require CAI.Macros

  def sid, do: System.get_env("SERVICE_ID")

  CAI.Macros.static_getter(:facility)
  CAI.Macros.static_getter(:vehicle)
  CAI.Macros.static_getter(:weapon)
  CAI.Macros.static_getter(:xp)

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
