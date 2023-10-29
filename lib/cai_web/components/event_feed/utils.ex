defmodule CAIWeb.EventFeed.Utils do
  @moduledoc """
  Helper/util functions for EventFeed.Components
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI.Guards, only: [is_character_id: 1]

  alias CAI.Characters.Character

  alias CAIWeb.Utils

  require Logger

  def link_character(maybe_character, opts \\ [])

  def link_character({:being_fetched, character_id}, opts) do
    link_character(%Character{character_id: character_id, name_first: "Getting name...", faction_id: 0}, opts)
  end

  def link_character({:unavailable, character_id}, opts) when is_character_id(character_id) do
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

  def link_character({:unavailable, npc_id}, _opts) do
    if npc_id == 0 do
      ""
    else
      assigns = %{npc_id: npc_id}

      ~H"""
      <span title={"NPC ID #{@npc_id}"}>a vehicle</span>
      """
    end
  end

  def link_character(%Character{name_first: name, character_id: id, faction_id: faction_id}, opts) do
    assigns = %{
      name: name,
      id: id,
      possessive: (Keyword.get(opts, :possessive?, false) && "'s") || "",
      faction_classes: Utils.faction_css_classes(faction_id, Keyword.get(opts, :team_id)),
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

  def loadout_icon(loadout_id) do
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

  def vehicle_icon(vehicle_id, character_name) do
    vehicle = CAI.get_vehicle(vehicle_id)

    assigns = %{
      icon_url: vehicle["logo_path"],
      title_text: "#{character_name} was in a #{vehicle["name"]} during this event"
    }

    ~H"""
    <img :if={@icon_url} src={@icon_url} alt={@title_text} title={@title_text} class="inline object-contain h-4" />
    """
  end

  def get_weapon_name(0, 0) do
    "a fall from a high place"
  end

  def get_weapon_name(0, _) do
    "a blunt force"
  end

  def get_weapon_name(weapon_id, _) do
    "#{CAI.get_weapon(weapon_id)["name"]}"
  end
end
