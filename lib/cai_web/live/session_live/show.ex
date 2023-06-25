defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAIWeb.ESSComponents

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{GainExperience, Death, VehicleDestroy}
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
          |> assign(:page_title, "#{character.name_first}'s Session")
          |> assign(:character, character)
        }

      :not_found ->
        {:noreply, assign(socket, :page_title, "Character not found!")}

      :error ->
        {:noreply,
         assign(
           socket,
           :page_title,
           "An error occured while looking up that character. Please try again."
         )}
    end
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    character = socket.assigns.character

    other =
      case get_other_character(character.character_id, event) do
        :noop ->
          :noop

        {{:ok, %Character{} = other}, _other_id} ->
          other

        {reason, other_id} ->
          put_flash(socket, :info, "Couldn't fetch the character for an event: #{reason}")
          {:unavailable, other_id}
      end

    {:noreply, stream_insert(socket, :events, {event, character, other}, at: 0)}
  end

  # Gets the character struct for the other character in this interaction (if there is one)
  defp get_other_character(this_char_id, %GainExperience{character_id: this_char_id} = ge) do
    {Characters.get_character(ge.other_id), ge.other_id}
  end

  defp get_other_character(this_char_id, %GainExperience{other_id: this_char_id} = ge) do
    {Characters.get_character(ge.character_id), ge.character_id}
  end

  defp get_other_character(this_char_id, %mod{character_id: this_char_id} = e)
       when mod in [Death, VehicleDestroy] do
    {Characters.get_character(e.attacker_character_id), e.attacker_character_id}
  end

  defp get_other_character(this_char_id, %mod{attacker_character_id: this_char_id} = e)
       when mod in [Death, VehicleDestroy] do
    {Characters.get_character(e.character_id), e.character_id}
  end

  defp get_other_character(_, _), do: :noop

  defp event_to_dom_id({event, _, _}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
