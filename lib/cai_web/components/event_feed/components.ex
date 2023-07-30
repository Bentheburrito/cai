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
  import CAIWeb.EventFeed.Utils

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

  attr(:entry, :map)
  attr(:id, :string)

  def entry(assigns) do
    ~H"""
    <% assigns =
      assigns
      |> Map.put(:character, @entry.character)
      |> Map.put(:other, @entry.other)
      |> Map.put(:event, @entry.event) %>
    <%= unless (log = entry_content(assigns, @entry.event)) == "" do %>
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
        <%= log %>
        <span :if={@entry.count > 1}>(x<%= @entry.count %>)</span>
        <%= for event <- @entry.bonuses do %>
          <%= render_bonus(assigns, event) %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Given an event and associated Character structs (where applicable), render a message
  defp entry_content(assigns, %BattleRankUp{}) do
    ~H"""
    <%= link_character(@character) %> ranked up to Battle Rank <%= @event.battle_rank %>
    """
  end

  # Suicide
  defp entry_content(assigns, %Death{character_id: char_id, attacker_character_id: char_id}) do
    ~H"""
    <%= link_character(@character,
      loadout_id: @event.character_loadout_id,
      team_id: @event.team_id,
      vehicle_id: @event.attacker_vehicle_id
    ) %> died of their own accord with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  defp entry_content(assigns, %Death{}) do
    ~H"""
    <% opts = [
      loadout_id: @event.attacker_loadout_id,
      team_id: @event.attacker_team_id,
      vehicle_id: @event.attacker_vehicle_id
    ] %>
    <%= link_character(@other, opts) %> killed
    <%= link_character(@character, loadout_id: @event.character_loadout_id, team_id: @event.team_id) %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  defp entry_content(assigns, %PlayerFacilityCapture{facility_id: facility_id}) do
    facility = CAI.get_facility(facility_id)

    facility_type_text =
      if facility["facility_type"] in ["Small Outpost", "Large Outpost", "Large CTF Outpost", "Small CTF Outpost"] do
        ""
      else
        facility["facility_type"]
      end

    assigns =
      Map.merge(
        %{
          facility: facility,
          facility_type: facility_type_text
        },
        assigns
      )

    ~H"""
    <%= link_character(@character) %> captured <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
    """
  end

  defp entry_content(assigns, %PlayerFacilityDefend{facility_id: facility_id}) do
    facility = CAI.get_facility(facility_id)

    facility_type_text =
      if facility["facility_type"] in ["Small Outpost", "Large Outpost", "Large CTF Outpost", "Small CTF Outpost"] do
        ""
      else
        facility["facility_type"]
      end

    assigns =
      Map.merge(
        %{
          facility: facility,
          facility_type: facility_type_text
        },
        assigns
      )

    ~H"""
    <%= link_character(@character) %> defended <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
    """
  end

  # Destroyed own vehicle
  defp entry_content(assigns, %VehicleDestroy{character_id: character_id, attacker_character_id: character_id}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.attacker_loadout_id, team_id: @event.team_id) %> destroyed their <%= CAI.get_vehicle(
      @event.vehicle_id
    )["name"] %> with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  defp entry_content(assigns, %VehicleDestroy{}) do
    ~H"""
    <% opts = [
      loadout_id: @event.attacker_loadout_id,
      team_id: @event.attacker_team_id,
      vehicle_id: @event.attacker_vehicle_id
    ] %>
    <%= link_character(@other, opts) %> destroyed
    <%= link_character(@character, team_id: @event.team_id, possessive?: true, vehicle_id: @event.vehicle_id) %>
    <%= CAI.get_vehicle(@event.vehicle_id)["name"] %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  # Kill assist
  defp entry_content(assigns, %GainExperience{experience_id: id}) when is_assist_xp(id) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id, team_id: @event.team_id) %> assisted in killing
    <%= link_character(@other) %>
    """
  end

  # Revived (or got revived by) someone
  defp entry_content(assigns, %GainExperience{experience_id: id}) when is_revive_xp(id) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> revived <%= link_character(@other) %>
    """
  end

  # Gunner gets a kill
  defp entry_content(assigns, %GainExperience{experience_id: id}) when is_gunner_assist_xp(id) do
    %{"description" => desc} = CAI.get_xp(id)

    clean_vehicle_gunner = fn raw ->
      case String.trim_trailing(raw, "Gunner") do
        "Lib " <> rest -> "Liberator " <> rest
        trimmed -> trimmed
      end
    end

    # {VehicleKilled} kill by {VehicleKiller} gunner{?}
    assigns =
      case String.split(desc, [" kill by ", " Kill by "]) do
        ["Player", vehicle_killer_gunner] ->
          %{vehicle_killer: clean_vehicle_gunner.(vehicle_killer_gunner)}

        [vehicle_killed, vehicle_killer_gunner] ->
          %{
            vehicle_killed: vehicle_killed,
            vehicle_killer: clean_vehicle_gunner.(vehicle_killer_gunner)
          }

        _ ->
          Logger.warning("Could not parse gunner assist xp for event log message: #{inspect(desc)}")

          %{}
      end
      |> Map.put(:desc, desc)
      |> Map.merge(assigns)

    ~H"""
    <%= cond do %>
      <% assigns[:vehicle_killed] -> %>
        <%= link_character(@character, loadout_id: @event.loadout_id, team_id: @event.team_id, possessive?: true) %>
        <%= @vehicle_killer %> gunner destroyed a <%= @vehicle_killed %>
      <% assigns[:vehicle_killer] -> %>
        <%= link_character(@character, loadout_id: @event.loadout_id, team_id: @event.team_id, possessive?: true) %>
        <%= @vehicle_killer %> gunner killed <%= link_character(@other) %>
      <% :else -> %>
        <%= @desc %>
    <% end %>
    """
  end

  @ctf_flag_cap 2133
  defp entry_content(assigns, %GainExperience{experience_id: @ctf_flag_cap}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> captured a flag for the
    <%= CAI.factions()[@event.team_id].alias %>
    """
  end

  @point_cap_ids [272, 557]
  defp entry_content(assigns, %GainExperience{experience_id: id}) when id in @point_cap_ids do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %>
    <%= if @event.experience_id == 272, do: "captured", else: "contributed to capturing" %> a point
    """
  end

  @heal 4
  defp entry_content(assigns, %GainExperience{experience_id: @heal}) do
    ~H"""
    <%= link_character(@character, team_id: @event.team_id, loadout_id: @event.loadout_id) %> healed
    <%= link_character(@other) %>
    """
  end

  @priority_kill_assist 371
  defp entry_content(assigns, %GainExperience{experience_id: @priority_kill_assist}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> assisted in killing a priority target,
    <%= link_character(@other) %>
    """
  end

  @spawn_point_kill [270, 1409]
  defp entry_content(assigns, %GainExperience{experience_id: @spawn_point_kill}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> destroyed an enemy
    <%= if @event.experience_id == 270, do: "spawn beacon", else: "router" %>
    """
  end

  @end_kill_streak 38
  defp entry_content(assigns, %GainExperience{experience_id: @end_kill_streak}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> ended
    <%= link_character(@other, possessive?: true) %> kill streak
    """
  end

  @domination 10
  defp entry_content(assigns, %GainExperience{experience_id: @domination}) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> is dominating <%= link_character(@other) %>
    """
  end

  defp entry_content(assigns, %PlayerLogin{}), do: ~H"<%= link_character(@character) %> logged in."

  defp entry_content(assigns, %PlayerLogout{}), do: ~H"<%= link_character(@character) %> logged out."

  defp entry_content(_, _), do: ""

  defp render_bonus(assigns, %GainExperience{} = ge) do
    assigns = Map.put(assigns, :ge, ge)

    ~H"""
    <img
      :for={{:ok, icon_url} <- [CAI.xp_icon(@ge.experience_id, @ge.team_id)]}
      src={icon_url}
      alt={CAI.get_xp(@ge.experience_id)["description"]}
      title={"#{CAI.get_xp(@ge.experience_id)["description"]}, #{@ge.amount} XP"}
      class="inline object-contain h-8"
    />
    """
  end

  defp render_bonus(assigns, %FacilityControl{} = fc) do
    assigns = Map.put(assigns, :fc, fc)

    ~H"""
    <%= if Map.get(@entry.event, :outfit_id) == @fc.outfit_id do %>
      <span :if={@character.outfit}>for their outfit, <%= Outfit.alias_or_name(@character.outfit) %></span>
    <% else %>
      <span :for={{:ok, outfit} <- [CAI.Characters.fetch_outfit(@fc.outfit_id)]}>
        <% control_type = if @fc.new_faction_id == @fc.old_faction_id, do: :def, else: :cap %>
        <%= if control_type == :def, do: "for", else: "with" %> <%= Outfit.alias_or_name(outfit) %>
      </span>
    <% end %>
    """
  end
end
