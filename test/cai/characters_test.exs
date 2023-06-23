defmodule CAI.CharactersTest do
  use CAI.DataCase

  alias CAI.Characters

  describe "sessions" do
    alias CAI.Characters.Session

    import CAI.CharactersFixtures

    @invalid_attrs %{character: nil, faction_id: nil, name: nil}

    test "list_sessions/0 returns all sessions" do
      session = session_fixture()
      assert Characters.list_sessions() == [session]
    end

    test "get_session!/1 returns the session with given id" do
      session = session_fixture()
      assert Characters.get_session!(session.id) == session
    end

    test "create_session/1 with valid data creates a session" do
      valid_attrs = %{character: 42, faction_id: 42, name: "some name"}

      assert {:ok, %Session{} = session} = Characters.create_session(valid_attrs)
      assert session.character == 42
      assert session.faction_id == 42
      assert session.name == "some name"
    end

    test "create_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Characters.create_session(@invalid_attrs)
    end

    test "update_session/2 with valid data updates the session" do
      session = session_fixture()
      update_attrs = %{character: 43, faction_id: 43, name: "some updated name"}

      assert {:ok, %Session{} = session} = Characters.update_session(session, update_attrs)
      assert session.character == 43
      assert session.faction_id == 43
      assert session.name == "some updated name"
    end

    test "update_session/2 with invalid data returns error changeset" do
      session = session_fixture()
      assert {:error, %Ecto.Changeset{}} = Characters.update_session(session, @invalid_attrs)
      assert session == Characters.get_session!(session.id)
    end

    test "delete_session/1 deletes the session" do
      session = session_fixture()
      assert {:ok, %Session{}} = Characters.delete_session(session)
      assert_raise Ecto.NoResultsError, fn -> Characters.get_session!(session.id) end
    end

    test "change_session/1 returns a session changeset" do
      session = session_fixture()
      assert %Ecto.Changeset{} = Characters.change_session(session)
    end
  end
end
