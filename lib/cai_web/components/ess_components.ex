defmodule CAIWeb.ESSComponents do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI, only: [is_revive_xp: 1, is_assist_xp: 1, is_gunner_assist_xp: 1]

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

  attr(:event, :map)
  attr(:character, :map)
  attr(:other, :map)

  def event_item(assigns) do
    ~H"""
    <%= build_event_log_item(assigns, @event, @character.character_id) %>
    """
  end

  def build_event_log_item(assigns, %BattleRankUp{}, _c_id) do
    ~H"""
    <li>
      <%= link_character(@character) %> ranked up to <%= @event.battle_rank %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Suicide
  def build_event_log_item(
        assigns,
        %Death{character_id: char_id, attacker_character_id: char_id},
        _c_id
      ) do
    ~H"""
    <li>
      <%= link_character(@character) %> died of their own accord with <%= get_weapon_name(
        @event.attacker_weapon_id,
        @event.attacker_vehicle_id
      ) %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  def build_event_log_item(assigns, %Death{}, _c_id) do
    ~H"""
    <li>
      <%= link_character(
        if @character.character_id == @event.character_id, do: @other, else: @character
      ) %> killed <%= link_character(
        if @character.character_id == @event.character_id, do: @character, else: @other
      ) %> with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %>
      <%= (@event.is_headshot && "(headshot)") || "" %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
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
    # if cap.outfit_id == character.outfit.outfit_id do
    #   "for #{character.outfit.name}!"
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
    <li>
      <%= link_character(@character) %> captured <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
      <%= @capturing_outfit %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
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
    # if def.outfit_id == character.outfit.outfit_id do
    #   "for #{character.outfit.name}!"
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
    <li>
      <%= link_character(@character) %> defended <%= "#{@facility["facility_name"] || "a facility"} #{@facility_type}" %>
      <%= @capturing_outfit %> - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  # Destroyed own vehicle
  def build_event_log_item(
        assigns,
        %VehicleDestroy{character_id: character_id, attacker_character_id: character_id},
        _c_id
      ) do
    ~H"""
    <li>
      <%= link_character(@character) %> destroyed their <%= CAI.vehicles()[
        @event.vehicle_id
      ]["name"] %> with <%= get_weapon_name(@event.attacker_weapon_id, @event.attacker_vehicle_id) %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  def build_event_log_item(assigns, %VehicleDestroy{}, _c_id) do
    ~H"""
    <li>
      <%= link_character(
        if @character.character_id == @event.character_id, do: @other, else: @character
      ) %> destroyed <%= link_character(
        if @character.character_id == @event.character_id, do: @character, else: @other
      ) %>'s <%= CAI.vehicles()[@event.vehicle_id]["name"] %> with <%= get_weapon_name(
        @event.attacker_weapon_id,
        @event.attacker_vehicle_id
      ) %>
      <%= (@event.attacker_vehicle_id != 0 &&
             " while in a #{CAI.vehicles()[@event.attacker_vehicle_id]["name"]}") || "" %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Kill assist
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, character_id: char_id},
        char_id
      )
      when is_assist_xp(id) do
    ~H"""
    <li>
      <%= link_character(@character) %> assisted in killing <%= link_character(@other) %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Got revived by someone
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, other_id: char_id},
        char_id
      )
      when is_revive_xp(id) do
    ~H"""
    <li>
      <%= link_character(@other) %> revived <%= link_character(@character) %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Revived someone
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, character_id: char_id},
        char_id
      )
      when is_revive_xp(id) do
    ~H"""
    <li>
      <%= link_character(@character) %> revived <%= link_character(@other) %> - <%= hook_timestamp(
        @event.timestamp
      ) %>
    </li>
    """
  end

  # Gunner gets a kill
  def build_event_log_item(
        assigns,
        %GainExperience{experience_id: id, character_id: char_id},
        char_id
      )
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
          Logger.warning(
            "Could not parse gunner assist xp for event log message: #{inspect(desc)}"
          )

          %{}
      end
      |> Map.put(:desc_downcase, desc_downcase)
      |> Map.merge(assigns)

    ~H"""
    <li>
      <%= cond do %>
        <% @vehicle_killed -> %>
          <%= link_character(@character) %>'s <%= @vehicle_killer %> gunner destroyed a <%= @vehicle_killed %>
        <% @vehicle_killer -> %>
          <%= link_character(@character) %>'s <%= @vehicle_killer %> gunner killed <%= link_character(
            @other
          ) %>
        <% :else -> %>
          <%= @desc_downcase %>
      <% end %>
      - <%= hook_timestamp(@event.timestamp) %>
    </li>
    """
  end

  def build_event_log_item(assigns, %PlayerLogin{}, _c_id) do
    ~H"""
    <li><%= link_character(@character) %> logged in.</li>
    """
  end

  def build_event_log_item(assigns, %PlayerLogout{}, _c_id) do
    ~H"""
    <li><%= link_character(@character) %> logged out.</li>
    """
  end

  def build_event_log_item(_, _, _), do: ""

  defp link_character({:unavailable, character_id}) do
    assigns = %{character_id: character_id}

    ~H"""
    <a patch={~p"/sessions/#{@character_id}"}>[Character Name Unavailable]</a>
    """
  end

  defp link_character(%Character{name_first: name, character_id: id}) do
    assigns = %{name: name, id: id}

    ~H"""
    <.link patch={~p"/sessions/#{@id}"}><%= @name %></.link>
    """
  end

  defp get_weapon_name(0, 0) do
    "a fall from a high place"
  end

  defp get_weapon_name(0, _) do
    "the surface of Auraxis"
  end

  defp get_weapon_name(weapon_id, _) do
    "#{CAI.weapons()[weapon_id]["name"]}"
  end
end
