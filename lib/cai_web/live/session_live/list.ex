defmodule CAIWeb.SessionLive.List do
  alias CAIWeb.SessionLive
  use CAIWeb, :live_view

  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.Helpers
  alias CAI.ESS.PlayerLogout
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:sessions, dom_id: &boundary_tuple_to_dom_id/1)
     |> assign(:pinned, :loading)}
  end

  @impl true
  def handle_params(%{"character_id" => character_id}, _url, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, _c, timestamps} <- Characters.get_session_boundaries(character.character_id) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns[:character] do
          PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.character.character_id}")
        end

        PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
      end

      {
        :noreply,
        socket
        |> stream(:sessions, timestamps)
        |> assign(:character, character)
        |> assign(:page_title, "#{character.name_first}'s Session List")
        |> assign(:online?, Helpers.online?(character.character_id, timestamps))
      }
    end
  end

  @impl true
  def handle_event("toggle-pin-status", _unsigned_params, %{assigns: %{pinned: :loading}} = socket),
    do: {:noreply, socket}

  @impl true
  def handle_event("toggle-pin-status", _unsigned_params, socket) do
    character_id = socket.assigns.character.character_id
    pinned = socket.assigns.pinned

    new_pinned =
      if is_map_key(pinned, character_id) do
        Map.delete(pinned, character_id)
      else
        Map.put(pinned, character_id, :present)
      end

    {:noreply,
     socket
     |> assign(:pinned, new_pinned)
     |> push_event("set-pinned", %{"pinned" => new_pinned |> Map.keys() |> Enum.join(",")})}
  end

  @impl true
  def handle_event("set-pinned", %{"pinned" => idstr}, socket) do
    {:noreply, assign(socket, :pinned, SessionLive.parse_id_str(idstr))}
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{data: %PlayerLogout{}}}, socket) do
    {:noreply, assign(socket, :online?, false)}
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{}}, socket) do
    {:noreply, assign(socket, :online?, true)}
  end

  defp boundary_tuple_to_dom_id({login, logout}) do
    "session-#{login}-#{logout}"
  end
end
