defmodule CAIWeb.ESSComponents do
  use Phoenix.Component

  import CAI, only: [is_revive_xp: 1]

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

  def hook_timestamp(:loading), do: "Loading..."
  def hook_timestamp(nil), do: ""
  def hook_timestamp(:current_session), do: "Current Session"

  def hook_timestamp(timestamp) do
    timestamp
    # dt_string =
    #   timestamp
    #   |> DateTime.from_unix!()
    #   |> to_string()

    # id = :rand.uniform(999_999_999)

    # assigns = []

    # ~H"""
    # <span class="date-time" id={"formatted-timestamp-#{id}"} phx-hook="NewDateToFormat"><%= dt_string %></span>
    # """
  end

  attr :event, :map
  attr :character, :map
  attr :character_map, :map

  def event_item(assigns) do
    ~H"""
    <%= build_event_log_item(assigns, @event, @character) %>
    """
  end

  def build_event_log_item(assigns, %BattleRankUp{}, _c) do
    ~H"""
    <li>
      <%= link_character(@character.name_first) %> ranked up to <%= @event.battle_rank %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Suicide
  def build_event_log_item(
        assigns,
        %Death{
          character_id: character_id,
          attacker_character_id: character_id
        },
        _c
      ) do
    ~H"""
    <li>
      <%= get_character_name(assigns, @character.character_id) %> seems to have killed themself with <%= get_weapon_name(
        @event.attacker_weapon_id
      ) %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  def build_event_log_item(assigns, %Death{}, _c) do
    ~H"""
    <li>
      <%= get_character_name(assigns, @event.attacker_character_id) %> killed <%= get_character_name(
        assigns,
        @event.character_id
      ) %> with <%= get_weapon_name(@event.attacker_weapon_id) %>
      <%= (@event.is_headshot && "(headshot)") || "" %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  # def build_event_log_item(
  #       assigns,
  #       %PlayerFacilityCapture{}
  #     ) do
  #   facility = CAI.facilities()[@event.facility_id]

  #   facility_type_text =
  #     if facility["facility_type"] in ["Small Outpost", "Large Outpost"] do
  #       ""
  #     else
  #       facility["facility_type"]
  #     end

  #   # can't do this right now, need outfit ID from FacilityControl events (the one provided here is just the player's
  #   # current outfit :/)
  #   outfit_captured_text = ""
  #   # if cap.outfit_id == character.outfit.outfit_id do
  #   #   "for #{character.outfit.name}!"
  #   # else
  #   #   ""
  #   # end

  #   ~H"""
  #   <li>
  #     <%= link_character(character.name_first) %> captured <%= "#{facility["facility_name"] || "a facility"} #{facility_type_text}" %>
  #     <%= outfit_captured_text %> - <%= hook_timestamp(cap.timestamp) %>
  #   </li>
  #   """
  # end

  # def build_event_log_item(assigns, %PlayerFacilityDefend{}) do
  #   facility = CAI.facilities()[def.facility_id]

  #   facility_type_text =
  #     if facility["facility_type"] in ["Small Outpost", "Large Outpost"] do
  #       ""
  #     else
  #       facility["facility_type"]
  #     end

  #   outfit_captured_text = ""
  #   # if def.outfit_id == character.outfit.outfit_id do
  #   #   "for #{character.outfit.name}!"
  #   # else
  #   #   ""
  #   # end

  #   ~H"""
  #   <li>
  #     <%= link_character(character.name_first) %> defended <%= "#{facility["facility_name"] || "a facility"} #{facility_type_text}" %>
  #     <%= outfit_captured_text %> - <%= hook_timestamp(def.timestamp) %>
  #   </li>
  #   """
  # end

  # Destroyed own vehicle
  def build_event_log_item(
        assigns,
        %VehicleDestroy{character_id: character_id, attacker_character_id: character_id},
        _c
      ) do
    # CAI.vehicles()[@event.vehicle_id]["name"]
    ~H"""
    <li>
      <%= get_character_name(assigns, @character.character_id) %> destroyed their <%= @event.vehicle_id %> with <%= get_weapon_name(
        @event.attacker_weapon_id
      ) %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  def build_event_log_item(assigns, %VehicleDestroy{}, _c) do
    # CAI.vehicles()[@event.vehicle_id]["name"]
    # CAI.vehicles()[vd.attacker_vehicle_id]["name"]
    ~H"""
    <li>
      <%= get_character_name(assigns, @event.attacker_character_id) %> destroyed <%= get_character_name(
        assigns,
        @event.character_id
      ) %>'s <%= @event.vehicle_id %> with <%= get_weapon_name(@event.attacker_weapon_id) %>
      <%= (@event.attacker_vehicle_id != 0 &&
             " while in a #{@event.attacker_vehicle_id}") || "" %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # # Kill assist
  # def build_event_log_item(
  #       assigns,
  #       %GainExperience{experience_id: id, character_id: character_id} = ge,
  #       %Character{character_id: character_id},
  #       character_map
  #     )
  #     when is_assist_xp(id) do
  #   other_identifier = get_character_name(assigns, ge.other_id)
  #   character_identifier = get_character_name(assigns, character_id)

  #   ~H"""
  #   <li>
  #     <%= character_identifier %> assisted in killing <%= other_identifier %> - <%= hook_timestamp(
  #       ge.timestamp
  #     ) %>
  #   </li>
  #   """
  # end

  # Got revived by someone
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, other_id: character_id},
        %Character{character_id: character_id}
      )
      when is_revive_xp(id) do
    ~H"""
    <li>
      <%= get_character_name(assigns, @event.character_id) %> revived <%= get_character_name(
        assigns,
        @character.character_id
      ) %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  # Revived someone
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, character_id: character_id},
        %Character{character_id: character_id}
      )
      when is_revive_xp(id) do
    ~H"""
    <li>
      <%= get_character_name(assigns, @character.character_id) %> revived <%= get_character_name(
        assigns,
        @event.other_id
      ) %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  # # Gunner gets a kill
  # def build_event_log_item(
  #       assigns,
  #       %GainExperience{experience_id: id, character_id: character_id} = ge,
  #       %Character{character_id: character_id},
  #       character_map
  #     )
  #     when is_gunner_assist_xp(id) do
  #   other_identifier = get_character_name(assigns, ge.other_id)
  #   character_identifier = get_character_name(assigns, character_id)

  #   %{"description" => desc} = CAI.xp()[id]
  #   desc_downcase = String.downcase(desc)
  #   # {VehicleKilled} kill by {VehicleKiller} gunner{?}
  #   event_log_message =
  #     case String.split(desc_downcase, " kill by ") do
  #       ["player", vehicle_killer_gunner] ->
  #         vehicle_killer = String.trim_trailing(vehicle_killer_gunner, "gunner")

  #         ~H"<%= character_identifier %>'s <%= vehicle_killer %> gunner killed <%= other_identifier %>"

  #       [vehicle_killed, vehicle_killer_gunner] ->
  #         vehicle_killer = String.trim_trailing(vehicle_killer_gunner, "gunner")

  #         ~H"<%= character_identifier %>'s <%= vehicle_killer %> gunner destroyed a <%= vehicle_killed %>"

  #       _ ->
  #         Logger.warning(
  #           "Could not parse gunner assist xp for event log message: #{inspect(desc)}"
  #         )

  #         ~H"<%= desc %>"
  #     end

  #   ~H"""
  #   <li>
  #     <%= event_log_message %> - <%= hook_timestamp(ge.timestamp) %>
  #   </li>
  #   """
  # end

  def build_event_log_item(assigns, %PlayerLogin{}, _c) do
    ~H"""
    <li><%= link_character(@character.name_first) %> logged in.</li>
    """
  end

  def build_event_log_item(assigns, %PlayerLogout{}, _c) do
    ~H"""
    <li><%= link_character(@character.name_first) %> logged out.</li>
    """
  end

  def build_event_log_item(_, _, _), do: ""

  defp get_character_name(assigns, 0) do
    ~H"""
    [Unknown Character]
    """
  end

  defp get_character_name(assigns, character_id) do
    case assigns.character_map do
      %{^character_id => {:ok, %Character{name_first: name}}} ->
        link_character(name)

      _ ->
        link_character(character_id, " (Character Search Failed)")
    end
  end

  defp link_character(identifier, note \\ "") do
    # need `assigns` map in scope to use ~H
    assigns = %{identifier: identifier, note: note}

    ~H"""
    <a href={"/character/#{@identifier}"}><%= @identifier %></a><%= @note %>
    """
  end

  defp get_weapon_name(0) do
    assigns = %{}
    ~H"[Unknown Weapon]"
  end

  defp get_weapon_name(weapon_id) do
    assigns = %{weapon_id: weapon_id}

    ~H"""
    <%= @weapon_id %> <%!-- <%= CAI.weapons()[weapon_id]["name"] %> --%>
    """
  end
end
