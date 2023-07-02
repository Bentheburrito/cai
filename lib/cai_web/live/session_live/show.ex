defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAIWeb.ESSComponents
  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{GainExperience, Death, VehicleDestroy}
  alias Phoenix.PubSub

  @events_at 0
  @events_limit 15

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:live?, false)
      |> stream_configure(:events, dom_id: &event_to_dom_id/1)
    }
  end

  # Historical Session
  @impl true
  def handle_params(
        %{"character_id" => character_id, "login" => login, "logout" => logout},
        _,
        socket
      ) do
    with {:ok, login} <- parse_int_param(login, socket),
         {:ok, logout} <- parse_int_param(logout, socket),
         {:ok, %Character{} = character} <- get_character(character_id, socket) do
      # methinks to make things simple for these historical sections, just load all of the events into the stream.
      # no pagination.
      {
        :noreply,
        socket
        |> stream(:events, [], reset: true, at: @events_at, limit: @events_limit)
        |> assign(:page_title, "#{character.name_first}'s Previous Session")
        |> assign(:bounds, {login, logout})
        |> assign(:character, character)
      }
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket) do
      # Unsubscribe from the previously tracked character (if there is one)
      if socket.assigns[:character] do
        PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.character.character_id}")
      end

      if connected?(socket) do
        PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
      end

      {
        :noreply,
        socket
        |> stream(:events, [], at: @events_at, limit: @events_limit)
        |> assign(:page_title, "#{character.name_first}'s Session")
        |> assign(:live?, true)
        |> assign(:character, character)
      }
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

    {:noreply,
     stream_insert(socket, :events, {event, character, other},
       at: @events_at,
       limit: @events_limit
     )}
  end

  # Gets the character struct for the other character in this interaction (if there is one)
  defp get_other_character(this_char_id, %GainExperience{character_id: this_char_id} = ge) do
    {Characters.fetch(ge.other_id), ge.other_id}
  end

  defp get_other_character(this_char_id, %GainExperience{other_id: this_char_id} = ge) do
    {Characters.fetch(ge.character_id), ge.character_id}
  end

  defp get_other_character(this_char_id, %mod{character_id: this_char_id} = e)
       when mod in [Death, VehicleDestroy] do
    {Characters.fetch(e.attacker_character_id), e.attacker_character_id}
  end

  defp get_other_character(this_char_id, %mod{attacker_character_id: this_char_id} = e)
       when mod in [Death, VehicleDestroy] do
    {Characters.fetch(e.character_id), e.character_id}
  end

  defp get_other_character(_, _), do: :noop

  defp event_to_dom_id({event, _, _}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
