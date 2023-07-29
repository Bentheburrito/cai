defmodule CAIWeb.Utils do
  @moduledoc """
  Utility functions. If a function can fail, it will return a {:noreply, socket} tuple.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias CAI.Characters
  alias CAI.Characters.Character

  def get_character(character_id_string, socket) do
    with {:ok, character_id} <- parse_int_param(character_id_string, socket),
         {:ok, %Character{}} = ok <- Characters.fetch(character_id) do
      ok
    else
      :not_found ->
        {:noreply, assign(socket, :page_title, "Character not found!")}

      :error ->
        {:noreply,
         socket
         |> assign(:page_title, "Uh Oh :(")
         |> put_flash(
           :error,
           "An error occured while looking up that character. Please try again."
         )}

      noreply_tuple ->
        noreply_tuple
    end
  end

  def parse_int_param(param, socket) do
    case Integer.parse(param) do
      {parsed, ""} ->
        {:ok, parsed}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "#{param} is not a number!")
         |> assign(:page_title, "#{param} is not a number!")}
    end
  end

  def format_duration(start_seconds, end_seconds) do
    total_seconds = end_seconds - start_seconds
    seconds = total_seconds |> rem(3600) |> rem(60)
    minutes = total_seconds |> rem(3600) |> div(60)
    hours = div(total_seconds, 3600)

    [{hours, "hours"}, {minutes, "minutes"}, {seconds, "seconds"}]
    |> Stream.filter(fn {duration, _unit} -> duration > 0 end)
    |> Stream.map(fn {duration, unit} -> "#{duration} #{unit}" end)
    |> Enum.join(" ")
  end

  def safe_divide(num, denom) when denom in [0, 0.0], do: num / 1
  def safe_divide(num, denom), do: num / denom

  # Can't actually store these classes in `CAI.factions` because these classes won't be compiled...
  def faction_css_classes(faction_id, team_id) do
    case {CAI.factions()[faction_id].alias, team_id} do
      {"NS" <> _, 1} -> "bg-gradient-to-r from-gray-600 to-purple-600 hover:bg-gray-800"
      {"NS" <> _, 2} -> "bg-gradient-to-r from-gray-600 to-blue-600 hover:bg-gray-800"
      {"NS" <> _, 3} -> "bg-gradient-to-r from-gray-600 to-red-600 hover:bg-gray-800"
      {"NS" <> _, _} -> "bg-gray-600 hover:bg-gray-800"
      {"NC", _} -> "bg-blue-600 hover:bg-blue-800"
      {"VS", _} -> "bg-purple-600 hover:bg-purple-800"
      {"TR", _} -> "bg-red-600 hover:bg-red-800"
      _ -> "bg-gray-600 hover:bg-gray-800"
    end
  end
end
