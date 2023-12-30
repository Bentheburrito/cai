defmodule CAIWeb.EventFeed.Components do
  @moduledoc """
  Functions for rendering ESS data, like Event Feed entries.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI.Guards, only: [is_revive_xp: 1, is_assist_xp: 1, is_gunner_assist_xp: 1]
  import CAIWeb.CoreComponents, only: [hover_timestamp: 1]
  import CAIWeb.SessionComponents

  alias CAI.Characters.Outfit

  alias CAI.ESS.{
    BattleRankUp,
    Death,
    FacilityControl,
    GainExperience,
    PlayerFacilityCapture,
    PlayerFacilityDefend,
    PlayerLogin,
    PlayerLogout,
    VehicleDestroy
  }

  require Logger

  attr(:entry, :map, required: true)
  attr(:id, :string, required: true)

  def entry(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={
        Phoenix.LiveView.JS.transition(
          "animate-fade rounded-l pl-1",
          time: 1000
        )
      }
    >
      <.hover_timestamp id={"#{@id}-timestamp"} unix_timestamp={@entry.event.timestamp} />
      <.entry_content character={@entry.character} entry={@entry} event={@entry.event} other={@entry.other} />
      <span :if={@entry.count > 1}>(x<%= @entry.count %>)</span>
      <%= for event <- @entry.bonuses do %>
        <.render_bonus character={@entry.character} event={event} />
      <% end %>
    </div>
    """
  end

  defp entry_content(%{event: %BattleRankUp{}} = assigns) do
    ~H"""
    <.link_character character={@character} /> ranked up to Battle Rank <%= @event.battle_rank %>
    """
  end

  # Suicide
  defp entry_content(%{event: %Death{character_id: char_id, attacker_character_id: char_id}} = assigns) do
    ~H"""
    <.link_character
      character={@character}
      loadout_id={@event.character_loadout_id}
      team_id={@event.team_id}
      vehicle_id={@event.attacker_vehicle_id}
    /> died of their own accord with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  # Out of Bounds
  defp entry_content(%{event: %Death{character_id: char_id, attacker_character_id: 0}} = assigns) do
    ~H"""
    <.link_character
      character={@character}
      loadout_id={@event.character_loadout_id}
      team_id={@event.team_id}
      vehicle_id={@event.attacker_vehicle_id}
    /> went somewhere they're not supposed to go
    """
  end

  defp entry_content(%{event: %Death{}} = assigns) do
    ~H"""
    <.link_character
      character={@other}
      loadout_id={@event.attacker_loadout_id}
      team_id={@event.attacker_team_id}
      vehicle_id={@event.attacker_vehicle_id}
    /> killed <.link_character character={@character} loadout_id={@event.character_loadout_id} team_id={@event.team_id} />
    with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  defp entry_content(%{event: %mod{}} = assigns) when mod in [PlayerFacilityCapture, PlayerFacilityDefend] do
    ~H"""
    <.link_character character={@character} />
    <%= if match?(%PlayerFacilityCapture{}, @event), do: "captured", else: "defended" %>
    <%= CAI.get_facility(@event.facility_id)["facility_name"] || "a facility" %>
    <%= @event.facility_id
    |> CAI.get_facility()
    |> Map.get("facility_type", "")
    |> String.replace(["Small Outpost", "Large Outpost", "Large CTF Outpost", "Small CTF Outpost"], "") %>
    """
  end

  # Destroyed own vehicle
  defp entry_content(
         %{event: %VehicleDestroy{character_id: character_id, attacker_character_id: character_id}} = assigns
       ) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.attacker_loadout_id} team_id={@event.attacker_team_id} />
    destroyed their <%= CAI.get_vehicle(@event.vehicle_id)["name"] %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  defp entry_content(%{event: %VehicleDestroy{}} = assigns) do
    ~H"""
    <.link_character
      character={@other}
      loadout_id={@event.attacker_loadout_id}
      team_id={@event.attacker_team_id}
      vehicle_id={@event.attacker_vehicle_id}
    /> destroyed
    <.link_character character={@character} team_id={@event.team_id} possessive?={true} vehicle_id={@event.vehicle_id} />
    <%= CAI.get_vehicle(@event.vehicle_id)["name"] %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  # Kill assist
  defp entry_content(%{event: %GainExperience{experience_id: id}} = assigns) when is_assist_xp(id) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} team_id={@event.team_id} /> assisted in killing
    <.link_character character={@other} />
    """
  end

  # Revived (or got revived by) someone
  defp entry_content(%{event: %GainExperience{experience_id: id}} = assigns) when is_revive_xp(id) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> revived <.link_character character={@other} />
    """
  end

  # Gunner gets a kill
  defp entry_content(%{event: %GainExperience{experience_id: id}} = assigns) when is_gunner_assist_xp(id) do
    # {VehicleKilled} kill by {VehicleKiller} gunner{?}
    ~H"""
    <%= @event.experience_id
    |> CAI.get_xp()
    |> Map.get("desc", "")
    |> String.split([" kill by ", " Kill by "])
    |> case do %>
      <% ["Player", vehicle_killer_gunner] -> %>
        <.link_character character={@character} loadout_id={@event.loadout_id} team_id={@event.team_id} possessive?={true} />
        <%= clean_vehicle_gunner(vehicle_killer_gunner) %> gunner killed <.link_character character={@other} />
      <% [vehicle_killed, vehicle_killer_gunner] -> %>
        <.link_character character={@character} loadout_id={@event.loadout_id} team_id={@event.team_id} possessive?={true} />
        <%= clean_vehicle_gunner(vehicle_killer_gunner) %> gunner destroyed a <%= vehicle_killed %>
      <% _ -> %>
        <%= CAI.get_xp(@event.experience_id)["desc"] %>
    <% end %>
    """
  end

  @ctf_flag_cap 2133
  defp entry_content(%{event: %GainExperience{experience_id: @ctf_flag_cap}} = assigns) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> captured a flag for the
    <%= CAI.factions()[@event.team_id].alias %>
    """
  end

  @point_cap_ids [272, 557]
  defp entry_content(%{event: %GainExperience{experience_id: id}} = assigns) when id in @point_cap_ids do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} />
    <%= if @event.experience_id == 272, do: "captured", else: "contributed to capturing" %> a point
    """
  end

  @heal 4
  defp entry_content(%{event: %GainExperience{experience_id: @heal}} = assigns) do
    ~H"""
    <.link_character character={@character} team_id={@event.team_id} loadout_id={@event.loadout_id} /> healed
    <.link_character character={@other} />
    """
  end

  @priority_kill_assist 371
  defp entry_content(%{event: %GainExperience{experience_id: @priority_kill_assist}} = assigns) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> assisted in killing a priority target,
    <.link_character character={@other} />
    """
  end

  @spawn_point_kills [270, 1409]
  defp entry_content(%{event: %GainExperience{experience_id: id}} = assigns) when id in @spawn_point_kills do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> destroyed an enemy
    <%= if @event.experience_id == 270, do: "spawn beacon", else: "router" %>
    """
  end

  @end_kill_streak 38
  defp entry_content(%{event: %GainExperience{experience_id: @end_kill_streak}} = assigns) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> ended
    <.link_character character={@other} possessive?={true} /> kill streak
    """
  end

  @domination 10
  defp entry_content(%{event: %GainExperience{experience_id: @domination}} = assigns) do
    ~H"""
    <.link_character character={@character} loadout_id={@event.loadout_id} /> is dominating
    <.link_character character={@other} />
    """
  end

  @saved 336
  defp entry_content(%{event: %GainExperience{experience_id: @saved}} = assigns) do
    ~H"""
    <.link_character character={@character} team_id={@event.team_id} loadout_id={@event.loadout_id} /> was saved by
    <.link_character character={@other} />
    """
  end

  defp entry_content(%{event: %GainExperience{}} = assigns) do
    ~H"""
    <.link_character character={@character} team_id={@event.team_id} loadout_id={@event.loadout_id} />
    gained <%= @event.amount %>
    <span title={"XP ID: #{@event.experience_id}"}><%= CAI.get_xp(@event.experience_id)["description"] %> XP</span>
    <.link_character character={@other} prepend="via" />
    """
  end

  defp entry_content(%{event: %FacilityControl{}} = assigns) do
    ~H"<.facility_control event={@event} facility_info={CAI.get_facility(@event.facility_id)} />"
  end

  defp entry_content(%{event: %PlayerLogin{}} = assigns), do: ~H"<.link_character character={@character} /> logged in"

  defp entry_content(%{event: %PlayerLogout{}} = assigns), do: ~H"<.link_character character={@character} /> logged out"

  defp entry_content(assigns), do: ~H"A <%= @event.__struct__ %> event occurred"

  attr(:character, :map, required: true)
  attr(:event, :map, required: true)

  defp render_bonus(%{event: %GainExperience{}} = assigns) do
    ~H"""
    <img
      :for={{:ok, icon_url} <- [CAI.xp_icon(@event.experience_id, @event.team_id)]}
      src={icon_url}
      alt={CAI.get_xp(@event.experience_id)["description"]}
      title={"#{CAI.get_xp(@event.experience_id)["description"]}, #{@event.amount} XP"}
      class="inline object-contain h-8"
    />
    """
  end

  defp render_bonus(%{event: %FacilityControl{}} = assigns) do
    ~H"""
    <%= if is_map(@character) and is_map(@character.outfit) and Map.get(@character.outfit, :outfit_id) == @event.outfit_id do %>
      <span :if={@character.outfit}>for their outfit, <%= Outfit.alias_or_name(@character.outfit) %></span>
    <% else %>
      <span :for={{:ok, outfit} <- [CAI.Characters.fetch_outfit(@event.outfit_id)]}>
        <% control_type = if @event.new_faction_id == @event.old_faction_id, do: :def, else: :cap %>
        <%= if control_type == :def, do: "for", else: "with" %> <%= Outfit.alias_or_name(outfit) %>
      </span>
    <% end %>
    """
  end

  defp clean_vehicle_gunner(raw) do
    case String.trim_trailing(raw, "Gunner") do
      "Lib " <> rest -> "Liberator " <> rest
      trimmed -> trimmed
    end
  end
end
