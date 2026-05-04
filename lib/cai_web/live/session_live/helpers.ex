defmodule CAIWeb.SessionLive.Helpers do
  @moduledoc """
  Helper functions for SessionLive
  """
  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router,
    statics: CAIWeb.static_paths()

  import Phoenix.LiveView

  alias CAI.ESS.Helpers

  alias CAI.Characters
  alias CAIWeb.SessionLive.{Blurbs, Entry}
  alias CAIWeb.SessionLive.Show.Model

  require Logger

  @prepend 0
  @append -1
  @events_limit 15

  def handle_ess_event(socket, entry) do
    %{character_id: character_id} = character = socket.assigns.model.character

    other =
      character_id
      |> Helpers.get_other_character_id(entry.event)
      |> Entry.async_fetch_presentable_character()

    entry =
      case entry.event do
        %{character_id: ^character_id} -> Entry.new(entry.event, character, other, entry.count, entry.addl_events)
        _ -> Entry.new(entry.event, other, character, entry.count, entry.addl_events)
      end

    {
      :noreply,
      socket
      |> stream_insert(:events, entry, at: @prepend, limit: @events_limit)
      |> update_pending_queries(other, {:entry, entry})
      # |> Model.put(:last_entry, entry)
    }
  end

  # Given a list of events, this fn tries to split at `preferred_limit`, however, it might take more if events can be
  # grouped together as a single entry.
  def split_events_while(events, preferred_limit) do
    split_events_while(_taken = [], _remaining = events, _num_taken = 0, preferred_limit)
  end

  def split_events_while(taken, [], num_taken, _preferred_limit) do
    {Enum.reverse(taken), [], num_taken}
  end

  def split_events_while(
        [%{timestamp: t} | _] = taken,
        [%{timestamp: t} = next | remaining],
        num_taken,
        preferred_limit
      ) do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  def split_events_while(taken, [next | remaining], num_taken, preferred_limit) when num_taken < preferred_limit do
    split_events_while([next | taken], remaining, num_taken + 1, preferred_limit)
  end

  def split_events_while(taken, remaining, num_taken, _preferred_limit) do
    {Enum.reverse(taken), remaining, num_taken}
  end

  def get_session_history(character_id, login, socket) do
    case CAI.game_session(character_id, login) do
      {:ok, session} ->
        {:ok, session}

      {:error, error} ->
        Logger.error("Could not build a session for #{character_id}: #{inspect(error)}")

        {:noreply,
         socket
         |> put_flash(:error, "Unable to load that session right now. Please try again")
         |> push_navigate(to: ~p"/sessions/#{character_id}")}
    end
  end

  def push_login_blurb(socket) do
    with {:enabled, %Blurbs{} = blurbs} <- socket.assigns.model.blurbs,
         {:ok, track_filename} <- Blurbs.get_random_blurb_filename("login", blurbs) do
      push_event(socket, "play-blurb", %{"track" => track_filename})
    else
      _ -> socket
    end
  end

  def bulk_append(entries_to_stream, character, new_events_limit) do
    liveview = self()

    Task.start_link(fn ->
      other_character_ids =
        Stream.flat_map(
          entries_to_stream,
          fn entry ->
            Stream.concat(
              entry.event |> Map.take([:character_id, :attacker_character_id, :other_id]) |> Map.values(),
              Stream.flat_map(
                entry.addl_events,
                &(&1 |> Map.take([:character_id, :attacker_character_id, :other_id]) |> Map.values())
              )
            )
          end
        )
        |> MapSet.new()
        |> MapSet.difference(MapSet.new([nil, 0, character.character_id]))

      character_map = other_character_ids |> Characters.get_many() |> Map.put(character.character_id, character)

      entries = Entry.map_entries(entries_to_stream, character_map)
      send(liveview, {:bulk_append, entries, new_events_limit})
    end)
  end

  def update_entries(%Entry{} = entry, update_char_fn, socket) do
    %{character_id: character_id} = socket.assigns.model.character

    new_socket =
      case entry.event do
        %{character_id: ^character_id} ->
          update_entry(socket, %Entry{entry | other: update_char_fn.(entry.other)})

        _ ->
          update_entry(socket, %Entry{entry | character: update_char_fn.(entry.character)})
      end

    new_socket
  end

  def update_aggregate(field, update_char_fn, socket) do
    Model.update(socket, :aggregates, &update_in(&1, [field, :character], update_char_fn))
  end

  def build_entries_from_group({_, _, _, _} = pending_key, group, socket) do
    character = socket.assigns.model.character
    entries = Entry.from_groups(%{pending_key => group}, [], %{character.character_id => character})

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  def build_entries_from_group(pending_key, group, socket) do
    character = socket.assigns.model.character

    group_event = Map.get_lazy(group, :event, fn -> group |> Map.get(:bonuses, []) |> List.first() end)
    other_id = Helpers.get_other_character_id(character.character_id, group_event)
    other = Entry.async_fetch_presentable_character(other_id)

    character_map = %{character.character_id => character, other_id => other}
    entries = Entry.from_groups(%{pending_key => group}, [], character_map)
    labeled_entries = Enum.map(entries, &{:entry, &1})

    {
      :noreply,
      socket
      |> Model.update(:pending_groups, &Map.delete(&1, pending_key))
      |> update_pending_queries(other, labeled_entries)
      |> stream(:events, entries, at: @prepend, limit: @events_limit)
    }
  end

  def update_entry(socket, entry) do
    socket
    |> stream_insert(:events, entry, at: @append)
  end

  def refresh_aggregate_characters(socket) do
    socket
  end

  def event_to_dom_id(%Entry{event: event}) do
    hash = :md5 |> :crypto.hash(inspect(event)) |> Base.encode16()
    "events-#{event.timestamp}-#{hash}"
  end

  defp update_pending_queries(socket, character, item_to_update) when not is_list(item_to_update),
    do: update_pending_queries(socket, character, [item_to_update])

  defp update_pending_queries(socket, character, items_to_update) do
    case character do
      %{state: {:loading, query}} ->
        Model.update(
          socket,
          :pending_queries,
          &Map.update(&1, query, items_to_update, fn items -> items_to_update ++ items end)
        )

      _ ->
        socket
    end
  end
end
