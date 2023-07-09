defmodule CAIWeb.SessionLive.Show do
  use CAIWeb, :live_view

  import CAI, only: [is_kill_xp: 1]
  import CAIWeb.ESSComponents
  import CAIWeb.Utils

  alias CAI.Characters
  alias CAI.Characters.Character
  alias CAI.ESS.{GainExperience, Death, VehicleDestroy}
  alias CAIWeb.SessionLive.Entry
  alias Phoenix.PubSub

  require Logger

  @prepend 0
  @append -1
  @events_limit 15

  ### MOUNT AND HANDLE_PARAMS ###

  @impl true
  def mount(_params, _session, socket) do
    {
      :ok,
      socket
      |> assign(:live?, false)
      |> assign(:loading_more?, false)
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
         {:ok, %Character{} = character} <- get_character(character_id, socket),
         {:ok, event_history} <- get_session_history(character.character_id, login, logout, socket) do
      {init_events, remaining_events, new_limit} = split_events_while(event_history, @events_limit)

      bulk_append(init_events, character, new_limit)

      {
        :noreply,
        socket
        |> stream(:events, [], reset: true, at: @append, limit: @events_limit)
        |> assign(:remaining_events, remaining_events)
        |> assign(:page_title, "#{character.name_first}'s Previous Session")
        |> assign(:bounds, {login, logout})
        |> assign(:character, character)
        |> assign(:live?, false)
        |> assign(:loading_more?, true)
      }
    end
  end

  # Live Session
  @impl true
  def handle_params(%{"character_id" => character_id}, _, socket) do
    with {:ok, %Character{} = character} <- get_character(character_id, socket) do
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
        |> stream(:events, [], at: @prepend, limit: @events_limit)
        |> assign(:page_title, "#{character.name_first}'s Session")
        |> assign(:live?, true)
        |> assign(:character, character)
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
      tuples = map_events_to_tuples(events_to_stream, character)
      send(liveview, {:bulk_append, tuples, new_events_limit})
    end)
  end

  # Historic Session - bulk insert the given event tuples
  @impl true
  def handle_info({:bulk_append, event_tuples, new_events_limit}, socket) do
    # TODO: to group related events into a single log in the event feed, will need to:
    # 1. add another element to each tuple in `event_tuples` that has additional text/logos to be appended to the log
    # (e.g. logo for priority kill, domination, ended killstreak, etc.) (*side note: at this point, should we have a
    # generic "Event" struct to hold all of this info instead of a 4-elem tuple?)
    # 2. before passing to the stream, look through `event_tuples`, and "combine" them, updating the 4th element in the
    # tuple as we go
    # 3. to ensure we load all events that need to be combined, we can't just take the first 15. Need to use
    # Enum.split_while to potentially get more than 15 if (for example) events 13-17 have the same timestamp. Make sure
    # to update `new_events_limit` in this case as well.
    # CAVEAT: for live sessions, how do we combine those events? do we queue/stall for a couple of seconds? Maybe using
    # a generic event struct (see *note), we could use the stream's updating function when the struct has an `:id`
    # field?
    {
      :noreply,
      socket
      |> stream(:events, event_tuples, at: @append, limit: new_events_limit)
      |> assign(:events_limit, new_events_limit)
      |> assign(:loading_more?, false)
    }
  end

  # Live Session - receive a new event via PubSub
  @impl true
  def handle_info({:event, %Ecto.Changeset{} = event_cs}, socket) do
    event = Ecto.Changeset.apply_changes(event_cs)
    character = socket.assigns.character

    other = get_other_character(character.character_id, event)

    {:noreply,
     stream_insert(socket, :events, Entry.new(event, character, other),
       at: @prepend,
       limit: @events_limit
     )}
  end

  ### HELPERS ###

  defp map_events_to_tuples(init_events, character) do
    other_character_ids =
      Stream.flat_map(
        init_events,
        &(Map.take(&1, [:character_id, :attacker_character_id, :other_id]) |> Map.values())
      )
      |> MapSet.new()
      |> MapSet.delete(nil)
      |> MapSet.delete(0)
      |> MapSet.delete(character.character_id)

    other_character_map = other_character_ids |> Characters.get_many() |> Map.put(character.character_id, character)

    init_events
    |> events_to_entries(character, other_character_map)
    |> Enum.reverse()
  end

  # entry point
  defp events_to_entries([e | init_events], character, other_char_map) do
    other =
      get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))

      events_to_entries([Entry.new(e, character, other)], init_events, character, other_char_map)
    end

  # exit condition (no remaining events)
  defp events_to_entries(mapped, [], _character, _other_char_map), do: mapped

  # when the prev_e and e timestamps match, let's check for a group of GEs + corresponding Death and condense them
  defp events_to_entries([%Entry{event: %{timestamp: t} = prev_e} | mapped], [%{timestamp: t} = e | rem_events], character, other_char_map) do
    # grouped_map looks like %{{timestamp, attacker_id, char_id} => %{death: %Death{}, supplemental: [%GE{}]}}
    {new_mapped, remaining} =
      condense_deaths_and_bonuses([prev_e, e | rem_events], mapped, %{}, _target_t = t, character, other_char_map)

    events_to_entries(new_mapped, remaining, character, other_char_map)
  end

  defp events_to_entries([%Entry{event: prev_e1} = prev_entry1, %Entry{event: prev_e2, count: prev_count} = prev_entry2 | mapped], [e | rem_events], character, other_char_map) do
    if consecutive?(prev_e1, prev_e2) do
      events_to_entries([%Entry{prev_entry2 | count: prev_count + 1} | mapped], [e | rem_events], character, other_char_map)
    else
      other = get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))
      events_to_entries([Entry.new(e, character, other), prev_entry1, prev_entry2 | mapped], rem_events, character, other_char_map)
    end
  end

  defp events_to_entries(mapped, [e | rem_events], character, other_char_map) do
    other = get_other_character(character.character_id, e, &Map.fetch(other_char_map, &1))
    events_to_entries([Entry.new(e, character, other) | mapped], rem_events, character, other_char_map)
  end

  # No more events to iterate
  defp condense_deaths_and_bonuses([], mapped, grouped, _target_t, character, other_char_map) do
    apply_grouped([], mapped, grouped, character, other_char_map)
  end

  # If timestamps are different, we're done here
  defp condense_deaths_and_bonuses([%{timestamp: t} | _] = rem_events, mapped, grouped, target_t, character, other_char_map) when t != target_t do
    apply_grouped(rem_events, mapped, grouped, character, other_char_map)
  end

  # If `event` is a Death or bonus GE related to a death, add it to `grouped` keyed by
  # {timestamp, attacker_id, victim_id}. Otherwise, append `event` to mapped
  defp condense_deaths_and_bonuses([event | rem_events], mapped, grouped, target_t, character, other_char_map) do
    case event do
      # put the death event for a grouped entry
      %Death{} ->
        new_grouped = Map.update(
          grouped,
          {event.timestamp, event.attacker_character_id, event.character_id},
          %{death: event, bonuses: []},
          &Map.put(&1, :death, event)
        )

        condense_deaths_and_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # put a bonus event for a grouped entry
      %GainExperience{experience_id: id} when is_kill_xp(id) ->
        new_grouped = Map.update(
          grouped,
          {event.timestamp, event.character_id, event.other_id},
          %{death: nil, bonuses: [event]},
          &Map.update!(&1, :bonuses, fn bonuses -> [event | bonuses] end)
        )

        condense_deaths_and_bonuses(rem_events, mapped, new_grouped, target_t, character, other_char_map)

      # this event seems to be unrelated, so just append it to `mapped`
      _ ->
        other = get_other_character(character.character_id, event, &Map.fetch(other_char_map, &1))
        new_mapped = [Entry.new(event, character, other) | mapped]

        condense_deaths_and_bonuses(rem_events, new_mapped, grouped, target_t, character, other_char_map)
    end
  end

  defp apply_grouped(remaining, mapped, grouped, character, other_char_map) do
    new_mapped = for {_, %{death: d, bonuses: bonuses}} <- grouped, reduce: mapped do
      acc ->
        # If we didn't find a death associated with these bonuses, just put the bonuses back as regular entries.
        if is_nil(d) do
          other = get_other_character(character.character_id, List.first(bonuses), &Map.fetch(other_char_map, &1))
          Enum.map(bonuses, &Entry.new(&1, character, other)) ++ acc
        else
          other = get_other_character(character.character_id, d, &Map.fetch(other_char_map, &1))
          [Entry.new(d, character, other, 1, bonuses) | acc]
        end
    end

    {new_mapped, remaining}
  end

  defp consecutive?(%mod1{} = e1, %mod2{} = e2) do
    mod1 == mod2 and
      Map.get(e1, :character_id) == Map.get(e2, :character_id) and
      Map.get(e1, :attacker_character_id) == Map.get(e2, :attacker_character_id) and
      Map.get(e1, :other_id) == Map.get(e2, :other_id) and
      Map.get(e1, :experience_id) == Map.get(e2, :experience_id)
  end

  defp split_events_while(events, preferred_limit) do
    split_events_while(_taken = [], _remaining = events, _num_taken = 0, preferred_limit)
  end

  defp split_events_while(taken, [], num_taken, _preferred_limit) do
    {Enum.reverse(taken), [], num_taken}
  end

  defp split_events_while([%{timestamp: t} | _] = taken, [%{timestamp: t} = next | remaining], num_taken, preferred_limit) do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  defp split_events_while(taken, [next | remaining], num_taken, preferred_limit) when num_taken < preferred_limit do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  defp split_events_while(taken, remaining, num_taken, _preferred_limit) do
    {Enum.reverse(taken), remaining, num_taken}
  end

  defp get_session_history(character_id, login, logout, socket) do
    case Characters.get_session_history(character_id, login, logout) do
      events when is_list(events) ->
        {:ok, events}

      {:error, changeset} ->
        Logger.error(
          "Unable to get session history because of a changeset error building the session: #{inspect(changeset)}"
        )

        {:noreply,
         socket
         |> put_flash(:error, "Unable to load that session right now. Please try again")
         |> push_navigate(to: ~p"/sessions/#{character_id}")}
    end
  end

  # Gets the character struct for the other character in this interaction (if there is one)
  defp get_other_character(this_char_id, event, fetch_fn \\ &Characters.fetch/1)

  defp get_other_character(this_char_id, event, fetch_fn) do
    case do_get_other_character(this_char_id, event, fetch_fn) do
      :noop ->
        :noop

      {{:ok, %Character{} = other}, _other_id} ->
        other

      {{:ok, :not_found}, other_id} ->
        Logger.info("Character ID not_found: #{other_id}")
        {:unavailable, other_id}

      {reason, other_id} ->
        if CAI.character_id?(other_id) do
          Logger.warning("Couldn't fetch other character (ID #{inspect(other_id)}) for an event: #{inspect(reason)}")
        end

        {:unavailable, other_id}
    end
  end

  defp do_get_other_character(this_char_id, %GainExperience{character_id: this_char_id} = ge, fetch_fn) do
    {fetch_fn.(ge.other_id), ge.other_id}
  end

  defp do_get_other_character(this_char_id, %GainExperience{other_id: this_char_id} = ge, fetch_fn) do
    {fetch_fn.(ge.character_id), ge.character_id}
  end

  defp do_get_other_character(this_char_id, %mod{character_id: this_char_id} = e, fetch_fn)
       when mod in [Death, VehicleDestroy] do
    {fetch_fn.(e.attacker_character_id), e.attacker_character_id}
  end

  defp do_get_other_character(this_char_id, %mod{attacker_character_id: this_char_id} = e, fetch_fn)
       when mod in [Death, VehicleDestroy] do
    {fetch_fn.(e.character_id), e.character_id}
  end

  defp do_get_other_character(_, _, _), do: :noop

  defp event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end
end
