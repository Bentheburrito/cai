defmodule CAIWeb.SessionComponents do
  @moduledoc """
  Helper/util functions for EventFeed.Components
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import CAI.Guards, only: [is_character_id: 1]

  alias CAI.Characters.Character
  alias CAI.ESS.FacilityControl

  alias CAIWeb.Utils

  require Logger

  attr(:event, :map, required: true)
  attr(:facility_info, :map, required: true)

  def facility_control(%{event: %FacilityControl{new_faction_id: f_id, old_faction_id: f_id}} = assigns) do
    ~H"""
    <%= @facility_info["facility_name"] %> was defended by the <%= CAI.factions()[@event.new_faction_id].alias %>
    """
  end

  def facility_control(assigns) do
    ~H"""
    <%= @facility_info["facility_name"] %> was captured by the
    <%= CAI.factions()[@event.new_faction_id].alias %> from the <%= CAI.factions()[@event.old_faction_id].alias %>
    """
  end

  attr(:character, :any, required: true)
  attr(:vehicle_id, :integer, default: 0)
  attr(:loadout_id, :integer, default: 0)
  attr(:team_id, :integer, default: 0)
  attr(:possessive?, :boolean, default: false)
  attr(:prepend, :string, default: "")

  def link_character(%{character: %{state: {:loading, _}}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/sessions/#{@character.character_id}"}
      class="rounded pl-1 pr-1 mr-1 bg-gray-800 hover:text-gray-400"
    >
      <.vehicle_icon vehicle_id={@vehicle_id} character_name="[Loading...]" />
      <.loadout_icon loadout_id={@loadout_id} /> Loading name...
    </.link>
    """
  end

  def link_character(%{character: %{state: :unavailable, character_id: 0}} = assigns), do: ~H""

  def link_character(%{character: %{state: :unavailable, character_id: id}} = assigns) when is_character_id(id) do
    ~H"""
    <%= @prepend %>
    <.link
      navigate={~p"/sessions/#{@character.character_id}"}
      class="rounded pl-1 pr-1 mr-1 bg-gray-800 hover:text-gray-400"
    >
      <.vehicle_icon vehicle_id={@vehicle_id} character_name="[Name Unavailable]" />
      <.loadout_icon loadout_id={@loadout_id} /> [Name Unavailable] <%= (@possessive? && "'s") || "" %>
    </.link>
    """
  end

  def link_character(%{character: %{state: :unavailable}} = assigns) do
    ~H"""
    <%= @prepend %>
    <span title={"NPC ID #{@character.character_id}"}>a vehicle</span>
    """
  end

  def link_character(%{character: %Character{}} = assigns) do
    ~H"""
    <%= @prepend %>
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

  def link_aggregates(assigns) do
    ~H"""
    <%= for {aggregate, value_descriptor} <- aggregate_fields(), @aggregates[aggregate].character.character_id != 0 do %>
      <%= aggregate |> Atom.to_string() |> String.capitalize() %>:
      <.link_character character={@aggregates[aggregate].character} />
      (<%= value_descriptor %> <%= @aggregates[aggregate].value %> times) <br />
    <% end %>
    """
  end

  defp aggregate_fields, do: [{:nemesis, "died to"}, {:vanquished, "killed"}]

  def get_weapon_name(0, 0), do: "a fall from a high place"
  def get_weapon_name(0, _), do: "a blunt force"
  def get_weapon_name(weapon_id, _), do: "#{CAI.get_weapon(weapon_id)["name"]}"
end
