defmodule CAIWeb.ESSComponents do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI, only: [is_character_id: 1, is_revive_xp: 1, is_assist_xp: 1, is_gunner_assist_xp: 1]
  import CAIWeb.CoreComponents, only: [hover_timestamp: 1]

  alias CAI.Characters.Character

  alias CAI.ESS.{
    BattleRankUp,
    Death,
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
    <% log_item_assigns =
      assigns
      |> Map.put(:character, @entry.character)
      |> Map.put(:other, @entry.other)
      |> Map.put(:event, @entry.event) %>
    <%= unless (log = build_event_log_item(log_item_assigns, @entry.event, @entry.character.character_id)) == "" do %>
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
        <span :if={not match?([], @entry.bonuses)}>
          [Bonuses: <%= Enum.map_join(@entry.bonuses, ", ", &CAI.xp()[&1.experience_id]["description"]) %>]
        </span>
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
    <%= link_character(@character, @event.team_id) %> died of their own accord with <%= get_weapon_name(
      @event.attacker_weapon_id,
      @event.attacker_vehicle_id
    ) %>
    """
  end

  def build_event_log_item(assigns, %Death{}, _c_id) do
    ~H"""
    <% {attacker, character} =
      if @character.character_id == @event.character_id, do: {@other, @character}, else: {@character, @other} %>
    <%= link_character(attacker, @event.attacker_team_id) %> killed <%= link_character(character, @event.team_id) %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    <%= (@event.is_headshot && "(headshot)") || "" %>
    """
  end

  def build_event_log_item(assigns, %PlayerFacilityCapture{facility_id: facility_id}, _c_id) do
    facility = CAI.facilities()[facility_id]

    facility_type_text =
      if facility["facility_type"] in ["Small Outpost", "Large Outpost"] do
        ""
      else
        facility["facility_type"]
      end

    # can't do this right now, need outfit ID from FacilityControl events (the one provided here is just the player's
    # current outfit :/)
    capturing_outfit = "[outfit unknown]"
    # if cap.outfit_id == assigns.character.outfit.outfit_id do
    #   "for #{assigns.character.outfit.name}!"
    # else
    #   ""
    # end

    assigns =
      Map.merge(
        %{
          facility: facility,
          facility_type: facility_type_text,
          capturing_outfit: capturing_outfit
        },
        assigns
      )

    ~H"""
    <%= link_character(@character) %> captured <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
    <%= @capturing_outfit %>
    """
  end

  def build_event_log_item(assigns, %PlayerFacilityDefend{facility_id: facility_id}, _c_id) do
    facility = CAI.facilities()[facility_id]

    facility_type_text =
      if facility["facility_type"] in ["Small Outpost", "Large Outpost"] do
        ""
      else
        facility["facility_type"]
      end

    capturing_outfit = "[outfit unknown]"
    # if def.outfit_id == assigns.character.outfit.outfit_id do
    #   "for #{assigns.character.outfit.name}!"
    # else
    #   ""
    # end

    assigns =
      Map.merge(
        %{
          facility: facility,
          facility_type: facility_type_text,
          capturing_outfit: capturing_outfit
        },
        assigns
      )

    ~H"""
    <%= link_character(@character) %> defended <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
    <%= @capturing_outfit %>
    """
  end

  # Destroyed own vehicle
  def build_event_log_item(
        assigns,
        %VehicleDestroy{character_id: character_id, attacker_character_id: character_id},
        _c_id
      ) do
    ~H"""
    <%= link_character(@character, @event.team_id) %> destroyed their <%= CAI.vehicles()[
      @event.vehicle_id
    ]["name"] %> with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    """
  end

  def build_event_log_item(assigns, %VehicleDestroy{}, _c_id) do
    ~H"""
    <% {attacker, character} =
      if @character.character_id == @event.character_id, do: {@other, @character}, else: {@character, @other} %>
    <%= link_character(attacker, @event.attacker_team_id) %> destroyed
    <%= link_character(character, @event.team_id, true) %>
    <%= CAI.vehicles()[@event.vehicle_id]["name"] %> with
    <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
    <%= (@event.attacker_vehicle_id != 0 &&
           " while in a #{CAI.vehicles()[@event.attacker_vehicle_id]["name"]}") || "" %>
    """
  end

  # Kill assist
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_assist_xp(id) do
    ~H"""
    <%= link_character(@character, @event.team_id) %> assisted in killing <%= link_character(@other) %>
    """
  end

  # Got revived by someone
  def build_event_log_item(assigns, %GainExperience{experience_id: id, other_id: char_id}, char_id)
      when is_revive_xp(id) do
    ~H"""
    <%= link_character(@other) %> revived <%= link_character(@character) %>
    """
  end

  # Revived someone
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_revive_xp(id) do
    ~H"""
    <%= link_character(@character) %> revived <%= link_character(@other) %>
    """
  end

  # Gunner gets a kill
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when is_gunner_assist_xp(id) do
    %{"description" => desc} = CAI.xp()[id]
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
      <% @vehicle_killed -> %>
        <%= link_character(@character, @event.team_id, true) %> <%= @vehicle_killer %> gunner destroyed a <%= @vehicle_killed %>
      <% @vehicle_killer -> %>
        <%= link_character(@character, @event.team_id, true) %> <%= @vehicle_killer %> gunner killed <%= link_character(
          @other
        ) %>
      <% :else -> %>
        <%= @desc_downcase %>
    <% end %>
    """
  end

  @ctf_flag_cap 2133
  def build_event_log_item(assigns, %GainExperience{experience_id: @ctf_flag_cap, character_id: char_id} = ge, char_id) do
    assigns = Map.put(assigns, :team_id, ge.team_id)

    ~H"""
    <%= link_character(@character) %> captured a flag for the <%= CAI.factions()[@team_id].alias %>
    """
  end

  @point_cap_ids [272, 557]
  def build_event_log_item(assigns, %GainExperience{experience_id: id, character_id: char_id}, char_id)
      when id in @point_cap_ids do
    assigns = Map.put(assigns, :action, (id == 272 && "captured") || "contributed to capturing")

    ~H"""
    <%= link_character(@character) %> <%= @action %> a point
    """
  end

  @heal 4
  def build_event_log_item(assigns, %GainExperience{experience_id: @heal}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> healed <%= link_character(
      if @character.character_id == @event.character_id, do: @other, else: @character
    ) %>
    """
  end

  @revenge_kill 11
  def build_event_log_item(assigns, %GainExperience{experience_id: @revenge_kill}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> got revenge on
    <%= link_character(if @character.character_id == @event.character_id, do: @other, else: @character) %>
    """
  end

  @priority_kill 279
  def build_event_log_item(assigns, %GainExperience{experience_id: @priority_kill}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> killed a priority target,
    <%= link_character(if @character.character_id == @event.character_id, do: @other, else: @character) %>
    """
  end

  @priority_kill_assist 371
  def build_event_log_item(assigns, %GainExperience{experience_id: @priority_kill_assist}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> assisted in killing a priority target,
    <%= link_character(if @character.character_id == @event.character_id, do: @other, else: @character) %>
    """
  end

  @spawn_beacon_kill 270
  def build_event_log_item(assigns, %GainExperience{experience_id: @spawn_beacon_kill}, _c_id) do
    ~H"""
    <%= link_character(@character) %> destroyed an enemy spawn beacon
    """
  end

  @end_kill_streak 38
  def build_event_log_item(assigns, %GainExperience{experience_id: @end_kill_streak}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> ended
    <%= link_character(if(@character.character_id == @event.character_id, do: @other, else: @character), true) %> kill streak
    """
  end

  @domination 10
  def build_event_log_item(assigns, %GainExperience{experience_id: @domination}, _c_id) do
    ~H"""
    <%= link_character(if @character.character_id == @event.character_id, do: @character, else: @other) %> is dominating
    <%= link_character(if @character.character_id == @event.character_id, do: @other, else: @character) %>
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

  defp link_character(maybe_character, team_id \\ :same_as_faction, possessive? \\ false)

  defp link_character({:unavailable, character_id}, _team_id, possessive?)
       when is_character_id(character_id) do
    assigns = %{character_id: character_id, possessive: (possessive? && "'s") || ""}

    ~H"""
    <.link patch={~p"/sessions/#{@character_id}"} class="hover:text-zinc-500">[Name Unavailable]<%= @possessive %></.link>
    """
  end

  defp link_character({:unavailable, npc_id}, _team_id, _) do
    if npc_id == 0 do
      ""
    else
      assigns = %{npc_id: npc_id}

      ~H"""
      <span title={"NPC ID #{@npc_id}"}>a vehicle</span>
      """
    end
  end

  defp link_character(
         %Character{name_first: name, character_id: id, faction_id: faction_id},
         team_id,
         possessive?
       ) do
    assigns = %{
      name: name,
      id: id,
      possessive: (possessive? && "'s") || "",
      # Can't actually store these classes in `CAI.factions` because these classes won't be compiled...
      faction_classes:
        case {CAI.factions()[faction_id].alias, team_id} do
          {"NS", 1} -> "bg-gradient-to-r from-gray-600 to-purple-600 hover:bg-gray-800"
          {"NS", 2} -> "bg-gradient-to-r from-gray-600 to-blue-600 hover:bg-gray-800"
          {"NS", 3} -> "bg-gradient-to-r from-gray-600 to-red-500 hover:bg-gray-800"
          {"NS", _} -> "bg-gray-600 hover:bg-gray-800"
          {"NSO", 1} -> "bg-gradient-to-r from-gray-600 to-purple-600 hover:bg-gray-800"
          {"NSO", 2} -> "bg-gradient-to-r from-gray-600 to-blue-600 hover:bg-gray-800"
          {"NSO", 3} -> "bg-gradient-to-r from-gray-600 to-red-500 hover:bg-gray-800"
          {"NSO", _} -> "bg-gray-600 hover:bg-gray-800"
          {"NC", _} -> "bg-blue-600 hover:bg-blue-800"
          {"VS", _} -> "bg-purple-600 hover:bg-purple-800"
          {"TR", _} -> "bg-red-500 hover:bg-red-800"
          _ -> "bg-gray-600 hover:bg-gray-800"
        end
    }

    ~H"""
    <.link patch={~p"/sessions/#{@id}"} class={"rounded pl-1 pr-1 mr-1 #{@faction_classes}"}>
      <%= @name <> @possessive %>
    </.link>
    """
  end

  defp get_weapon_name(0, 0) do
    "a fall from a high place"
  end

  defp get_weapon_name(0, _) do
    "a blunt force"
  end

  defp get_weapon_name(weapon_id, _) do
    "#{CAI.weapons()[weapon_id]["name"]}"
  end
end
