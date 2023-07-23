defmodule CAI.CharactersTest do
  use CAI.DataCase

  alias CAI.Characters

  describe "sessions" do
    alias CAI.Characters.Session

    import CAI.CharactersFixtures

    @snowful 5_428_713_425_545_165_425

    test "build/3 with valid data creates a session" do
      assert {:ok, %Session{} = session} = Session.build(@snowful, 1234, 2345)
      assert session.character_id == @snowful
    end

    test "build/3 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Session.build(nil, 1234, 2345)
    end
  end
end
