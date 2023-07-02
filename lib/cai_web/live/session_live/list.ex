defmodule CAIWeb.SessionLive.List do
  use CAIWeb, :live_view

  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_configure(socket, :sessions, dom_id: &boundary_tuple_to_dom_id/1)}
  end

  @impl true
  def handle_params(%{"character_id" => character_id}, _url, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, _c, timestamps} <- Characters.get_session_boundaries(character.character_id) do
      {
        :noreply,
        socket
        |> stream(:sessions, timestamps)
        |> assign(:character, character)
      }
    end
  end

  defp boundary_tuple_to_dom_id({login, logout}) do
    "session-#{login}-#{logout}"
  end
end
