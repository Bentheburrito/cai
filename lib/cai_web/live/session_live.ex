defmodule CAIWeb.SessionLive do
  use CAIWeb, :live_view

  alias CAI.Characters
  alias CAI.Characters.Character

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
    }
  end

  @impl true
  def handle_event("validate", %{"character-ref" => ref}, socket) do
    ref_errors = if String.length(ref) < 3, do: ["Character names must be at least 3 characters"], else: []

    {:noreply, socket |> assign(:ref, ref) |> assign(:ref_errors, ref_errors)}
  end

  @impl true
  def handle_event("search", %{"character-ref" => ref}, socket) do
    case Characters.fetch(ref) do
      {:ok, %Character{character_id: id}} ->
        {:noreply, push_navigate(socket, to: ~p"/sessions/#{id}")}

      :not_found ->
        {:noreply, put_flash(socket, :error, "Character not found. Please double check the spelling and try again.")}

      :error ->
        Logger.error("Error fetching a character when a user searched for #{ref}")
        {:noreply, put_flash(socket, :error, "Uh oh, something went wrong on our end. Please try again")}
    end
  end
end
