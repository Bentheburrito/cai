defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAIWeb.EventFeed.Components
  import CAIWeb.Utils
  import CAIWeb.SessionLive.Helpers

  alias CAI.ESS.{
    GainExperience,
    Helpers,
    MetagameEvent
  }

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.Characters.Session
  alias CAIWeb.SessionLive.Entry
  alias Phoenix.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15
  @time_update_interval 3000

  ### MOUNT AND HANDLE_PARAMS ###

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:live?, false)
      |> assign(:loading_more?, false)
      |> stream_configure(:events, dom_id: &CAIWeb.SessionLive.Helpers.event_to_dom_id/1)
    }
  end

  # Historical Session
  @impl true
  def handle_params(%{"character_id" => character_id, "login" => login, "logout" => logout}, _, socket) do
    with {:ok, login} <- parse_int_param(login, socket),
         {:ok, logout} <- parse_int_param(logout, socket),
         {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, session} <- Session.build(character.character_id, login, logout),
         {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
      {init_events, remaining_events, new_limit} = split_events_while(event_history, @events_limit)

      bulk_append(init_events, character, new_limit)

      {
        :noreply,
        socket
        |> assign(:aggregates, Map.take(session, Session.aggregate_fields()))
        |> assign(:character, character)
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> assign(:live?, false)
        |> assign(:loading_more?, true)
        |> assign(:page_title, "#{character.name_first}'s Previous Session")
        |> assign(:remaining_events, remaining_events)
        |> assign(:timestamps, {login, logout})
      }
    else
      {:error, changeset} ->
        bubbled_errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)

        Logger.error("Could not build session: #{inspect(bubbled_errors)}")

        {
          :noreply,
          socket
          |> put_flash(
            :error,
            "Something went wrong opening that character's session, please try again. #{CAI.please_report_msg()}"
          )
          |> push_navigate(to: ~p"/sessions/#{character_id}")
        }

      {:noreply, socket} ->
        {:noreply, socket}
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, _c, timestamps} <- Characters.get_session_boundaries(character.character_id, 1) do
      if connected?(socket) do
        # Unsubscribe from the previously tracked character (if there is one)
        if socket.assigns[:character] do
          PubSub.unsubscribe(CAI.PubSub, "ess:#{socket.assigns.character.character_id}")
        end

        PubSub.subscribe(CAI.PubSub, "ess:#{character.character_id}")
        PubSub.subscribe(CAI.PubSub, "ess:FacilityControl")
      end

      # If the character is currently online, let's build the session so far
      online? = Helpers.online?(character.character_id, timestamps)

      aggregates =
        with true <- online?,
             [{login, logout} | _] <- timestamps,
             {:ok, session} <- Session.build(character.character_id, login, logout),
             {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
          {init_events, _remaining_events, new_limit} = split_events_while(event_history, @events_limit)

          bulk_append(init_events, character, new_limit)

          Map.take(session, Session.aggregate_fields())
        else
          false ->
            Map.new(Session.aggregate_fields(), &{&1, 0})

          {:error, changeset} ->
            Logger.error("Could not build a session handling live session params: #{inspect(changeset)}")
            Map.new(Session.aggregate_fields(), &{&1, 0})

          [] ->
            Logger.error("""
            Tried to match `[{login, logout} | _]` from `timestamps = #{inspect(timestamps)}`, but got an empty list.
            #{character.name_first} (#{character.character_id}) was confirmed online, so there should have been at least one boundary pair:
            #{online?} = Helpers.online?(#{character.character_id}, #{inspect(timestamps)})
            """)

            Map.new(Session.aggregate_fields(), &{&1, 0})

          {:noreply, _socket} ->
            Map.new(Session.aggregate_fields(), &{&1, 0})
        end

      timestamps =
        case {online?, timestamps} do
          {true, [{login, logout}]} -> {login, logout}
          _ -> {:os.system_time(:second), :offline}
        end

      Process.send_after(self(), :time_update, @time_update_interval)

      {
        :noreply,
        socket
        |> assign(:aggregates, aggregates)
        |> assign(:character, character)
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> assign(:live?, true)
        |> assign(:page_title, "#{character.name_first}'s Session")
        |> assign(:pending_groups, %{})
        |> assign(:timestamps, timestamps)
      }
    end
  end

  ### HANDLE EVENTS AND MESSAGES ###

  # Make "Load More" button presses synchronous
  def handle_event("load-more-events", _params, %{assigns: %{loading_more?: true}} = socket) do
    {:noreply, socket}
  end

  # Stream some more events (if there are any) when "Load More" is clicked
  @impl true
  def handle_event("load-more-events", _params, socket) do
    case split_events_while(socket.assigns.remaining_events, @events_limit) do
      {[], _, _} ->
        {:noreply, assign(socket, :remaining_events, [])}

      {events_to_stream, remaining_events, events_limit} ->
        new_events_limit = Map.get(socket.assigns, :events_limit, @events_limit) + events_limit
        bulk_append(events_to_stream, socket.assigns.character, new_events_limit)

        {:noreply, socket |> assign(:remaining_events, remaining_events) |> assign(:loading_more?, true)}
    end
  end

  defp bulk_append(events_to_stream, character, new_events_limit) do
    liveview = self()

    Task.start_link(fn ->
      entries = Entry.map(events_to_stream, [character])
      send(liveview, {:bulk_append, entries, new_events_limit})
    end)
  end

  # Historic Session - bulk insert the given event tuples
  @impl true
  def handle_info({:bulk_append, entries, new_events_limit}, socket) do
    {
      :noreply,
      socket
      |> stream(:events, entries, at: @append, limit: new_events_limit)
      |> assign(:events_limit, new_events_limit)
      |> assign(:loading_more?, false)
    }
  end

  # Live Session - receive a new event via PubSub
  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    %{aggregates: aggregates, character: %{character_id: character_id}} = socket.assigns

    aggregates = Session.put_aggregate_event(event, aggregates, character_id)

    socket = assign(socket, :aggregates, aggregates)

    handle_ess_event(event, socket)
  end

  # Live Session - we've waited long enough to receive a primary event and any bonuses, so combine them into an Entry.
  @impl true
  def handle_info({:build_entries, pending_key}, socket) do
    case Map.fetch(socket.assigns.pending_groups, pending_key) do
      {:ok, group} ->
        character = socket.assigns.character

        character_map =
          with [%{character_id: _} | _] <- group.bonuses,
               {_, char_id, other_id} = pending_key,
               placeholder_event = %GainExperience{character_id: char_id, other_id: other_id},
               %Character{} = other <- Helpers.get_other_character(character.character_id, placeholder_event) do
            %{other.character_id => other}
          else
            {:unavailable, other_id} -> %{other_id => {:unavailable, other_id}}
            _ -> %{}
          end
          |> Map.put(character.character_id, character)

        entries = Entry.from_groups(%{pending_key => group}, [], character_map)

        {
          :noreply,
          socket
          |> update(:pending_groups, &Map.delete(&1, pending_key))
          |> stream(:events, entries, at: @prepend, limit: @events_limit)
        }

      :error ->
        Logger.error("Received :build_entries message, but no group was found under #{inspect(pending_key)}")
        {:noreply, socket}
    end
  end

  # Live Session - Update the `logout` time every few seconds, unless the character is no longer online.
  @impl true
  def handle_info(:time_update, socket) do
    last_entry =
      Map.get_lazy(socket.assigns, :last_entry, fn ->
        case socket.assigns.timestamps do
          {_login, :offline} -> Entry.new(%MetagameEvent{timestamp: 0}, %{})
          {_login, logout} -> Entry.new(%MetagameEvent{timestamp: logout}, %{})
        end
      end)

    if Helpers.online?(last_entry.event) do
      {login, _logout} = Map.fetch!(socket.assigns, :timestamps)
      Process.send_after(self(), :time_update, @time_update_interval)
      {:noreply, assign(socket, :timestamps, {login, :os.system_time(:second)})}
    else
      {:noreply, socket}
    end
  end
end
