defmodule CAIWeb.Utils do
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
end
