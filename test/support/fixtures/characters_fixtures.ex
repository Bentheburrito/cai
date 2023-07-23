defmodule CAI.CharactersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CAI.Characters` context.
  """

  alias CAI.Characters.Session
  alias CAI.DataCase

  @doc """
  Build a session.
  """
  def session_fixture(character_id \\ 5_428_713_425_545_165_425) do
    now = :os.system_time(:second)
    login = now - 5 * 60
    logout = now

    DataCase.insert_kills(character_id, login + 1)

    {:ok, session} = Session.build(character_id, login, logout)

    {session, login, logout}
  end
end
