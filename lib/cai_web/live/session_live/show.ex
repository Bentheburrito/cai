defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  alias CAI.Characters
  alias CAI.Characters.Character
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        stream_configure(socket, :events, dom_id: &event_to_dom_id/1)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    character_id = String.to_integer(character_id)

    case Characters.get_character(character_id) do
      {:ok, %Character{} = character} ->
        if connected?(socket) do
          PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
        end

        {
          :noreply,
          socket
          |> stream(:events, [], at: 0, limit: 2)
          |> assign(:page_title, page_title(socket.assigns.live_action))
          |> assign(:character, character)
        }

      :not_found ->
        {:noreply, assign(socket, :page_title, "Character not found!")}

      :error ->
        {:noreply,
         assign(
           socket,
           :page_title,
           "An error occured while looking up that character. Please try."
         )}
    end
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)

    {:noreply, stream_insert(socket, :events, event, at: 0)}
  end

  defp page_title(:show), do: "Show Session"
  defp page_title(:edit), do: "Edit Session"

  defp event_to_dom_id(event) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
