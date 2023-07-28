defmodule CAIWeb.ESSComponents do
  @moduledoc """
  Functions for rendering ESS data, like Event Feed entries.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI.Guards, only: [is_character_id: 1, is_revive_xp: 1, is_assist_xp: 1, is_gunner_assist_xp: 1]
  import CAIWeb.CoreComponents, only: [hover_timestamp: 1]

  alias CAI.Characters.Character
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

  def event_item(assigns) do
    ~H"""
    <% assigns =
      assigns
      |> Map.put(:character, @entry.character)
      |> Map.put(:other, @entry.other)
      |> Map.put(:event, @entry.event) %>
    <%= unless (log = build_event_log_item(assigns, @entry.event, @entry.character.character_id)) == "" do %>
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

  def build_event_log_item(assigns, %BattleRankUp{}, _c_id) do
    ~H"""
    <%= link_character(@character) %> ranked up to Battle Rank <%= @event.battle_rank %>
    """
  end

  # Suicide
  def build_event_log_item(assigns, %Death{character_id: char_id, attacker_character_id: char_id}, _c_id) do
    ~H"""
    <%= link_character(@character,
      loadout_id: @event.character_loadout_id,
      team_id: @event.team_id,
      vehicle_id: @event.attacker_vehicle_id
    ) %> died of their own accord with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  def build_event_log_item(assigns, %Death{}, _c_id) do
    ~H"""
    <% {attacker, character} =
      if @character.character_id == @event.character_id, do: {@other, @character}, else: {@character, @other} %>
    <%= link_character(attacker,
      loadout_id: @event.attacker_loadout_id,
      team_id: @event.attacker_team_id,
      vehicle_id: @event.attacker_vehicle_id
    ) %> killed <%= link_character(character, loadout_id: @event.character_loadout_id, team_id: @event.team_id) %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  def build_event_log_item(assigns, %PlayerFacilityCapture{facility_id: facility_id}, _c_id) do
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

  def build_event_log_item(assigns, %PlayerFacilityDefend{facility_id: facility_id}, _c_id) do
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
  def build_event_log_item(
        assigns,
        %VehicleDestroy{character_id: character_id, attacker_character_id: character_id},
        _c_id
      ) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.attacker_loadout_id, team_id: @event.team_id) %> destroyed their <%= CAI.get_vehicle(
      @event.vehicle_id
    )["name"] %> with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  def build_event_log_item(assigns, %VehicleDestroy{}, _c_id) do
    ~H"""
    <% {attacker, character} =
      if @character.character_id == @event.character_id, do: {@other, @character}, else: {@character, @other} %>
    <%= link_character(attacker,
      loadout_id: @event.attacker_loadout_id,
      team_id: @event.attacker_team_id,
      vehicle_id: @event.attacker_vehicle_id
    ) %> destroyed <%= link_character(character, team_id: @event.team_id, possessive?: true, vehicle_id: @event.vehicle_id) %>
    <%= CAI.get_vehicle(@event.vehicle_id)["name"] %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  # Kill assist
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_assist_xp(id) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id, team_id: @event.team_id) %> assisted in killing <%= link_character(
      @other
    ) %>
    """
  end

  # Got revived by someone
  def build_event_log_item(assigns, %GainExperience{experience_id: id, other_id: char_id}, char_id)
      when is_revive_xp(id) do
    ~H"""
    <%= link_character(@other, loadout_id: @event.loadout_id) %> revived <%= link_character(@character) %>
    """
  end

  # Revived someone
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_revive_xp(id) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> revived <%= link_character(@other) %>
    """
  end

  # Gunner gets a kill
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_gunner_assist_xp(id) do
    %{"description" => desc} = CAI.get_xp(id)
    desc_downcase = String.downcase(desc)

    # {VehicleKilled} kill by {VehicleKiller} gunner{?}
    assigns =
      case String.split(desc_downcase, " kill by ") do
        ["player", vehicle_killer_gunner] ->
          %{vehicle_killer: String.trim_trailing(vehicle_killer_gunner, "gunner")}

        [vehicle_killed, vehicle_killer_gunner] ->
          %{
            vehicle_killed: vehicle_killed,
            vehicle_killer: String.trim_trailing(vehicle_killer_gunner, "gunner")
          }

        _ ->
          Logger.warning("Could not parse gunner assist xp for event log message: #{inspect(desc)}")

          %{}
      end
      |> Map.put(:desc_downcase, desc_downcase)
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
        <%= @desc_downcase %>
    <% end %>
    """
  end

  @ctf_flag_cap 2133
  def build_event_log_item(assigns, %GainExperience{experience_id: @ctf_flag_cap, character_id: char_id} = ge, char_id) do
    assigns = Map.put(assigns, :team_id, ge.team_id)

    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> captured a flag for the <%= CAI.factions()[@team_id].alias %>
    """
  end

  @point_cap_ids [272, 557]
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when id in @point_cap_ids do
    assigns = Map.put(assigns, :action, (id == 272 && "captured") || "contributed to capturing")

    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> <%= @action %> a point
    """
  end

  @heal 4
  def build_event_log_item(assigns, %GainExperience{experience_id: @heal}, _c_id) do
    ~H"""
    <% {healer, healed} =
      if @character.character_id == @event.character_id, do: {@character, @other}, else: {@other, @character} %>
    <%= link_character(healer, team_id: @event.team_id, loadout_id: @event.loadout_id) %> healed <%= link_character(healed) %>
    """
  end

  @priority_kill_assist 371
  def build_event_log_item(assigns, %GainExperience{experience_id: @priority_kill_assist}, _c_id) do
    ~H"""
    <% {char, char_loadout} =
      if @character.character_id == @event.character_id, do: {@character, @event.loadout_id}, else: {@other, nil} %>
    <%= link_character(char, loadout_id: char_loadout) %> assisted in killing a priority target,
    <% {other, other_loadout} =
      if @character.character_id == @event.character_id, do: {@other, nil}, else: {@character, @event.loadout_id} %>
    <%= link_character(other, loadout_id: other_loadout) %>
    """
  end

  @spawn_beacon_kill 270
  def build_event_log_item(assigns, %GainExperience{experience_id: @spawn_beacon_kill}, _c_id) do
    ~H"""
    <%= link_character(@character, loadout_id: @event.loadout_id) %> destroyed an enemy spawn beacon
    """
  end

  @end_kill_streak 38
  def build_event_log_item(assigns, %GainExperience{experience_id: @end_kill_streak}, _c_id) do
    ~H"""
    <% {char, char_loadout} =
      if @character.character_id == @event.character_id, do: {@character, @event.loadout_id}, else: {@other, nil} %>
    <%= link_character(char, loadout_id: char_loadout) %> ended <% {other, other_loadout} =
      if @character.character_id == @event.character_id, do: {@other, nil}, else: {@character, @event.loadout_id} %>
    <%= link_character(other, loadout_id: other_loadout, possessive?: true) %> kill streak
    """
  end

  @domination 10
  def build_event_log_item(assigns, %GainExperience{experience_id: @domination}, _c_id) do
    ~H"""
    <% {char, char_loadout} =
      if @character.character_id == @event.character_id, do: {@character, @event.loadout_id}, else: {@other, nil} %>
    <%= link_character(char, loadout_id: char_loadout) %> is dominating
    <% {other, other_loadout} =
      if @character.character_id == @event.character_id, do: {@other, nil}, else: {@character, @event.loadout_id} %>
    <%= link_character(other, loadout_id: other_loadout) %>
    """
  end

  def build_event_log_item(assigns, %PlayerLogin{}, _c_id) do
    ~H"""
    <%= link_character(@character) %> logged in.
    """
  end

  def build_event_log_item(assigns, %PlayerLogout{}, _c_id) do
    ~H"""
    <%= link_character(@character) %> logged out.
    """
  end

  def build_event_log_item(_, _, _), do: ""

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
      <span>for their outfit, <%= Outfit.alias_or_name(@character.outfit) %></span>
    <% else %>
      <span :for={{:ok, outfit} <- [CAI.Characters.fetch_outfit(@fc.outfit_id)]}>
        <% control_type = if @fc.new_faction_id == @fc.old_faction_id, do: :def, else: :cap %>
        <%= if control_type == :def, do: "for", else: "with" %> <%= Outfit.alias_or_name(outfit) %>
      </span>
    <% end %>
    """
  end

  defp link_character(maybe_character, opts \\ [])

  defp link_character({:unavailable, character_id}, opts) when is_character_id(character_id) do
    possessive? = Keyword.get(opts, :possessive?, false)

    assigns = %{
      character_id: character_id,
      possessive: (possessive? && "'s") || "",
      loadout_icon: loadout_icon(Keyword.get(opts, :loadout_id)),
      vehicle_icon: vehicle_icon(Keyword.get(opts, :vehicle_id), "this character")
    }

    ~H"""
    <.link navigate={~p"/sessions/#{@character_id}"} class="rounded pl-1 pr-1 mr-1 bg-gray-800 hover:text-gray-400">
      <%= @vehicle_icon %>
      <%= @loadout_icon %> [Name Unavailable]<%= @possessive %>
    </.link>
    """
  end

  defp link_character({:unavailable, npc_id}, _opts) do
    if npc_id == 0 do
      ""
    else
      assigns = %{npc_id: npc_id}

      ~H"""
      <span title={"NPC ID #{@npc_id}"}>a vehicle</span>
      """
    end
  end

  defp link_character(%Character{name_first: name, character_id: id, faction_id: faction_id}, opts) do
    assigns = %{
      name: name,
      id: id,
      possessive: (Keyword.get(opts, :possessive?, false) && "'s") || "",
      faction_classes: faction_css_classes(faction_id, Keyword.get(opts, :team_id)),
      loadout_icon: loadout_icon(Keyword.get(opts, :loadout_id)),
      vehicle_icon: vehicle_icon(Keyword.get(opts, :vehicle_id), name)
    }

    ~H"""
    <.link navigate={~p"/sessions/#{@id}"} class={"rounded pl-1 pr-1 mr-1 #{@faction_classes}"}>
      <%= @vehicle_icon %>
      <%= @loadout_icon %>
      <%= @name <> @possessive %>
    </.link>
    """
  end

  # Can't actually store these classes in `CAI.factions` because these classes won't be compiled...
  defp faction_css_classes(faction_id, team_id) do
    case {CAI.factions()[faction_id].alias, team_id} do
      {"NS" <> _, 1} -> "bg-gradient-to-r from-gray-600 to-purple-600 hover:bg-gray-800"
      {"NS" <> _, 2} -> "bg-gradient-to-r from-gray-600 to-blue-600 hover:bg-gray-800"
      {"NS" <> _, 3} -> "bg-gradient-to-r from-gray-600 to-red-500 hover:bg-gray-800"
      {"NS" <> _, _} -> "bg-gray-600 hover:bg-gray-800"
      {"NC", _} -> "bg-blue-600 hover:bg-blue-800"
      {"VS", _} -> "bg-purple-600 hover:bg-purple-800"
      {"TR", _} -> "bg-red-500 hover:bg-red-800"
      _ -> "bg-gray-600 hover:bg-gray-800"
    end
  end

  defp loadout_icon(loadout_id) do
    class_name = CAI.loadouts()[loadout_id][:class_name]

    icon_url =
      case class_name do
        # 14985
        "Infiltrator" -> PS2.API.get_image_url("/files/ps2/images/static/204.png")
        # 14986
        "Light Assault" -> PS2.API.get_image_url("/files/ps2/images/static/62.png")
        # 14988
        "Medic" -> PS2.API.get_image_url("/files/ps2/images/static/65.png")
        # 14983
        "Engineer" -> PS2.API.get_image_url("/files/ps2/images/static/201.png")
        # 14984
        "Heavy Assault" -> PS2.API.get_image_url("/files/ps2/images/static/59.png")
        # 14987
        "MAX" -> PS2.API.get_image_url("/files/ps2/images/static/207.png")
        _ -> nil
      end

    assigns = %{icon_url: icon_url, class_name: class_name}

    ~H"""
    <img :if={@icon_url} src={@icon_url} alt={@class_name} title={@class_name} class="inline object-contain h-4" />
    """
  end

  defp vehicle_icon(vehicle_id, character_name) do
    vehicle = CAI.get_vehicle(vehicle_id)

    assigns = %{
      icon_url: vehicle["logo_path"],
      title_text: "#{character_name} was in a #{vehicle["name"]} during this event"
    }

    ~H"""
    <img :if={@icon_url} src={@icon_url} alt={@title_text} title={@title_text} class="inline object-contain h-4" />
    """
  end

  defp get_weapon_name(0, 0) do
    "a fall from a high place"
  end

  defp get_weapon_name(0, _) do
    "a blunt force"
  end

  defp get_weapon_name(weapon_id, _) do
    "#{CAI.get_weapon(weapon_id)["name"]}"
  end
end
