defmodule CAIWeb.SessionLive.List do
  use CAIWeb, :live_view

  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.PlayerLogout
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :sessions, dom_id: &boundary_tuple_to_dom_id/1)}
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
        |> assign(:online?, CAI.ESS.Helpers.online?(character.character_id, timestamps))
      }
    end
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
