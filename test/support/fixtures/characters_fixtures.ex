defmodule CAI.CharactersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CAI.Characters` context.
  """

  @doc """
  Generate a session.
  """
  def session_fixture(attrs \\ %{}) do
    {:ok, session} =
      attrs
      |> Enum.into(%{
        character: 42,
        faction_id: 42,
        name: "some name"
      })
      |> CAI.Characters.create_session()

    session
  end
end
