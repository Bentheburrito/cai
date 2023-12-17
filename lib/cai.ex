defmodule CAI do
  @moduledoc """
  CAI keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  require CAI.Macros

  import CAI.Guards, only: [is_dogfighter_xp: 1, is_vehicle_destruction_xp: 1]

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

  def xp_icon(id, _team_id) when is_dogfighter_xp(id),
    do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/77982.png")}

  def xp_icon(id, _team_id) when is_vehicle_destruction_xp(id),
    do: {:ok, PS2.API.get_image_url("/files/ps2/images/static/13909.png")}

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
        image: "/images/VS.png"
      },
      2 => %{
        name: "New Conglomerate",
        alias: "NC",
        color: 0x2A94F7,
        image: "/images/NC.png"
      },
      3 => %{
        name: "Terran Republic",
        alias: "TR",
        color: 0xE52D2D,
        image: "/images/TR.png"
      },
      4 => %{
        name: "Nanite Systems",
        alias: "NSO",
        color: 0xE5E5E5,
        image: "/images/NSO.png"
      }
    }

  def loadouts do
    %{
      1 => %{class_name: "Infiltrator", faction_id: 2, profile_id: 2},
      3 => %{class_name: "Light Assault", faction_id: 2, profile_id: 4},
      4 => %{class_name: "Medic", faction_id: 2, profile_id: 5},
      5 => %{class_name: "Engineer", faction_id: 2, profile_id: 6},
      6 => %{class_name: "Heavy Assault", faction_id: 2, profile_id: 7},
      7 => %{class_name: "MAX", faction_id: 2, profile_id: 8},
      8 => %{class_name: "Infiltrator", faction_id: 3, profile_id: 10},
      10 => %{class_name: "Light Assault", faction_id: 3, profile_id: 12},
      11 => %{class_name: "Medic", faction_id: 3, profile_id: 13},
      12 => %{class_name: "Engineer", faction_id: 3, profile_id: 14},
      13 => %{class_name: "Heavy Assault", faction_id: 3, profile_id: 15},
      14 => %{class_name: "MAX", faction_id: 3, profile_id: 16},
      15 => %{class_name: "Infiltrator", faction_id: 1, profile_id: 17},
      17 => %{class_name: "Light Assault", faction_id: 1, profile_id: 19},
      18 => %{class_name: "Medic", faction_id: 1, profile_id: 20},
      19 => %{class_name: "Engineer", faction_id: 1, profile_id: 21},
      20 => %{class_name: "Heavy Assault", faction_id: 1, profile_id: 22},
      21 => %{class_name: "MAX", faction_id: 1, profile_id: 23},
      28 => %{class_name: "Infiltrator", faction_id: 4, profile_id: 190},
      29 => %{class_name: "Light Assault", faction_id: 4, profile_id: 191},
      30 => %{class_name: "Medic", faction_id: 4, profile_id: 192},
      31 => %{class_name: "Engineer", faction_id: 4, profile_id: 193},
      32 => %{class_name: "Heavy Assault", faction_id: 4, profile_id: 194},
      45 => %{class_name: "MAX", faction_id: 4, profile_id: 252}
    }
  end

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
