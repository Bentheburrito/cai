defmodule CAIWeb.SessionLive do
  use CAIWeb, :live_view

  import CAIWeb.SessionComponents

  alias CAI.Characters
  alias CAI.Characters.{Character, PendingCharacter}

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <h3>Search for a character to see their current and previous sessions</h3>
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

    <h3>Pinned Characters</h3>
    <section id="pinned-characters-section" phx-hook="PinButton">
      <%= if is_map(@pinned) do %>
        <div :for={{_, character} <- @pinned}>
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

      send(liveview, {:pinned_fetched, character_map})
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
  def handle_info({:pinned_fetched, pinned}, socket) do
    {:noreply, assign(socket, :pinned, pinned)}
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
