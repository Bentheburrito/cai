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

  attr(:character, :any, required: true)
  attr(:vehicle_id, :integer, default: 0)
  attr(:loadout_id, :integer, default: 0)
  attr(:team_id, :integer, default: 0)
  attr(:possessive?, :boolean, default: false)

  def link_character(%{character: {:being_fetched, _character_id}} = assigns) do
    ~H"""
    <.link navigate={~p"/sessions/#{elem(@character, 1)}"} class="rounded pl-1 pr-1 mr-1 bg-gray-800 hover:text-gray-400">
      <.vehicle_icon vehicle_id={@vehicle_id} character_name="[Loading...]" />
      <.loadout_icon loadout_id={@loadout_id} /> Loading name...
    </.link>
    """
  end

  def link_character(%{character: {:unavailable, 0}} = assigns), do: ~H"someone or something"

  def link_character(%{character: {:unavailable, character_id}} = assigns) when is_character_id(character_id) do
    ~H"""
    <.link navigate={~p"/sessions/#{elem(@character, 1)}"} class="rounded pl-1 pr-1 mr-1 bg-gray-800 hover:text-gray-400">
      <.vehicle_icon vehicle_id={@vehicle_id} character_name="[Name Unavailable]" />
      <.loadout_icon loadout_id={@loadout_id} /> [Name Unavailable] <%= (@possessive? && "'s") || "" %>
    </.link>
    """
  end

  def link_character(%{character: {:unavailable, _}} = assigns) do
    ~H"""
    <span title={"NPC ID #{elem(@character, 1)}"}>a vehicle</span>
    """
  end

  def link_character(%{character: %Character{}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/sessions/#{@character.character_id}"}
      class={"rounded pl-1 pr-1 mr-1 #{Utils.faction_css_classes(@character.faction_id, @team_id)}"}
    >
      <.vehicle_icon vehicle_id={@vehicle_id} character_name={@character.name_first} />
      <.loadout_icon loadout_id={@loadout_id} />
      <%= "#{@character.name_first}#{(@possessive? && "'s") || ""}" %>
    </.link>
    """
  end

  attr(:loadout_id, :integer, required: true)

  def loadout_icon(assigns) do
    ~H"""
    <%= case CAI.loadouts()[@loadout_id][:class_name] do %>
      <% "Infiltrator" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/204.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% "Light Assault" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/62.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% "Medic" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/65.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% "Engineer" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/201.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% "Heavy Assault" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/59.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% "MAX" = class_name -> %>
        <img
          src={PS2.API.get_image_url("/files/ps2/images/static/207.png")}
          alt={class_name}
          title={class_name}
          class="inline object-contain h-4"
        />
      <% _ -> %>
        <%= nil %>
    <% end %>
    """
  end

  attr(:vehicle_id, :integer, required: true)
  attr(:character_name, :string, required: true)

  def vehicle_icon(assigns) do
    ~H"""
    <img
      :if={CAI.get_vehicle(@vehicle_id)["logo_path"]}
      src={CAI.get_vehicle(@vehicle_id)["logo_path"]}
      alt={"#{@character_name} was in a #{CAI.get_vehicle(@vehicle_id)["name"]} during this event"}
      title={"#{@character_name} was in a #{CAI.get_vehicle(@vehicle_id)["name"]} during this event"}
      class="inline object-contain h-4"
    />
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
