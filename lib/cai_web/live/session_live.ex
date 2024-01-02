defmodule CAIWeb.SessionLive do
  alias CAI.ESS.Helpers
  use CAIWeb, :live_view

  import CAIWeb.SessionComponents

  alias CAI.Characters
  alias CAI.Characters.{Character, PendingCharacter}
  alias CAI.ESS.PlayerLogout

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <.header>Search for a character to see their current and previous sessions</.header>
    <form phx-change="validate" phx-submit="search">
      <.input
        placeholder="Type a character name or ID here"
        class="text-zinc-900"
        id="character-ref"
        name="character-ref"
        value={@ref}
        type="text"
        errors={@ref_errors}
        autofocus
      />
      <.button class="mt-2 bg-gray-800">Search</.button>
    </form>

    <.header>Pinned Characters</.header>
    <section id="pinned-characters-section" phx-hook="PinButton">
      <%= if is_map(@pinned) do %>
        <div :for={
          {_, character} <-
            Enum.sort_by(
              @pinned,
              fn {id, char} -> {Map.get(@online_statuses, id) == :offline, char.name_first_lower} end
            )
        }>
          <%= if Map.get(@online_statuses, character.character_id, :offline) == :online do %>
            <span title={"#{character.name_first} is online"} class="animate-slow-blink">🔴</span>
          <% else %>
            <span title={"#{character.name_first} is offline"}>⚫</span>
          <% end %>

          <button
            id={"unpin-character-button-#{character.character_id}"}
            disabled={@pinned == :loading}
            class="p-1 rounded-2xl text-xs"
            phx-click="unpin-character"
            phx-value-character-id={character.character_id}
            title="Click to unpin this character"
          >
            📌
          </button>

          <.link_character character={character} team_id={Map.get(character, :faction_id, 0)} />
        </div>
      <% else %>
        Loading...
      <% end %>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:ref, "")
      |> assign(:ref_errors, [])
      |> assign(:page_title, "Search for a Character")
      |> assign(:pinned, :loading)
      |> assign(:online_statuses, %{})
    }
  end

  @impl true
  def handle_event("set-pinned", %{"pinned" => idstr}, socket) do
    pinned = parse_id_str(idstr)
    character_ids = Map.keys(pinned)

    liveview = self()

    Task.start_link(fn ->
      character_map =
        character_ids
        |> Characters.get_many()
        |> Map.new(fn
          {id, %Character{} = c} ->
            {id, c}

          {id, result} when result in [:not_found, :error] ->
            {id, %PendingCharacter{state: :unavailable, character_id: id}}
        end)

      online_statuses =
        Map.new(character_ids, fn id ->
          # TODO - if this leads to DB performance issues for users w/ lots of pinned chars, consider adding a
          # `:latest_events_by_character_id` cache.
          online? = id |> Characters.get_latest_event() |> Helpers.online?()
          {id, (online? && :online) || :offline}
        end)

      send(liveview, {:pinned_fetched, character_map, online_statuses})
    end)

    {:noreply, assign(socket, :pinned, pinned)}
  end

  @impl true
  def handle_event("validate", %{"character-ref" => ref}, socket) do
    ref_errors = validate(ref)

    {:noreply, socket |> clear_flash() |> assign(:ref, ref) |> assign(:ref_errors, ref_errors)}
  end

  # if the LV mounts, and the user just hits enter, put error
  @impl true
  def handle_event("search", %{"character-ref" => ""}, socket) do
    {:noreply, assign(socket, :ref_errors, ["Character names must be at least 3 characters"])}
  end

  @impl true
  def handle_event("search", %{"character-ref" => ref}, socket) do
    with [] <- validate(ref),
         {:ok, %Character{character_id: id}} <- Characters.fetch(ref) do
      {:noreply, push_navigate(socket, to: ~p"/sessions/#{id}")}
    else
      :not_found ->
        {:noreply, put_flash(socket, :error, "Character not found. Please double check the spelling and try again.")}

      :error ->
        Logger.error("Error fetching a character when a user searched for #{ref}")
        {:noreply, put_flash(socket, :error, "Uh oh, something went wrong on our end. Please try again")}

      ref_errors when is_list(ref_errors) ->
        {:noreply, assign(socket, :ref_errors, ref_errors)}
    end
  end

  @impl true
  def handle_event("unpin-character", %{"character-id" => character_id_str}, socket) do
    character_id = String.to_integer(character_id_str)
    pinned = Map.delete(socket.assigns.pinned, character_id)
    online_statuses = Map.delete(socket.assigns.online_statuses, character_id)

    {:noreply,
     socket
     |> assign(:pinned, pinned)
     |> assign(:online_statuses, online_statuses)
     |> push_event("set-pinned", %{"pinned" => pinned |> Map.keys() |> Enum.join(",")})}
  end

  @impl true
  def handle_info({:pinned_fetched, pinned, online_statuses}, socket) do
    for {character_id, _} <- online_statuses, do: Phoenix.PubSub.subscribe(CAI.PubSub, "ess:#{character_id}")
    {:noreply, socket |> assign(:pinned, pinned) |> assign(:online_statuses, online_statuses)}
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{data: %PlayerLogout{}} = cs}, socket) do
    {:noreply, update(socket, :online_statuses, &Map.put(&1, cs.changes.character_id, :offline))}
  end

  @impl true
  def handle_info({:event, %Ecto.Changeset{} = cs}, socket) do
    {:noreply, update(socket, :online_statuses, &Map.put(&1, cs.changes.character_id, :online))}
  end

  def parse_id_str(idstr) do
    idstr
    |> String.split(",", trim: true)
    |> Map.new(fn id ->
      character_id = String.to_integer(id)
      {character_id, %PendingCharacter{state: {:loading, nil}, character_id: character_id}}
    end)
  end

  defp validate(ref) do
    validators = [
      {String.length(ref) < 3, "Character names must be at least 3 characters"},
      {String.contains?(ref, " "), "Character names cannot contain spaces"}
    ]

    for {true, error} <- validators, do: error
  end
end
