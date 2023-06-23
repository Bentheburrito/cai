defmodule CAIWeb.SessionLive.Index do
  use CAIWeb, :live_view

  alias CAI.Characters
  alias CAI.Characters.Session

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :sessions, Characters.list_sessions())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Session")
    |> assign(:session, Characters.get_session!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Session")
    |> assign(:session, %Session{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Sessions")
    |> assign(:session, nil)
  end

  @impl true
  def handle_info({CAIWeb.SessionLive.FormComponent, {:saved, session}}, socket) do
    {:noreply, stream_insert(socket, :sessions, session)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    session = Characters.get_session!(id)
    {:ok, _} = Characters.delete_session(session)

    {:noreply, stream_delete(socket, :sessions, session)}
  end
end
