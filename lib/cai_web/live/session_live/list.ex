defmodule CAIWeb.SessionLive.List do
  alias CAIWeb.SessionLive
  use CAIWeb, :live_view

  import CAIWeb.Utils

  alias CAI.Character.GameSession
  alias CAI.Character.GameSessionList
  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.Event
  alias CAI.Event.PlayerLogout
  alias CAI.PubSub
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :pinned, :loading)}
  end

  @impl true
  def handle_params(%{"character_id" => character_id}, _url, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         %GameSessionList{} = gsl <- CAI.game_sessions(character.character_id) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns[:character] do
          PubSub.unsubscribe(PubSub.character_event(socket.assigns.character.character_id))
        end

        PubSub.subscribe(PubSub.character_event(character.character_id))
      end

      session_timestamps =
        Enum.map(gsl.sessions, fn %GameSession{} = session -> {session.began_at, session.ended_at} end)

      {
        :noreply,
        socket
        |> assign(:sessions, session_timestamps)
        |> assign(:character, character)
        |> assign(:page_title, "#{character.name_first}'s Session List")
        |> assign(:online?, Characters.online?(character.character_id))
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
  def handle_info({:event_handled, %Event{struct: %PlayerLogout{}}}, socket) do
    {:noreply, assign(socket, :online?, false)}
  end

  @impl true
  def handle_info({:event_handled, %Event{}}, socket) do
    {:noreply, assign(socket, :online?, true)}
  end
end
