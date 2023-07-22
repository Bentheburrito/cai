defmodule CAIWeb.SessionLiveTest do
  use CAIWeb.ConnCase

  import Phoenix.LiveViewTest
  import CAI.CharactersFixtures

  @create_attrs %{character: 42, faction_id: 42, name: "some name"}
  @update_attrs %{character: 43, faction_id: 43, name: "some updated name"}
  @invalid_attrs %{character: nil, faction_id: nil, name: nil}

  defp create_session(_) do
    {session, login, logout} = session_fixture()
    %{session: session, login: login, logout: logout}
  end

  describe "List" do
    setup [:create_session]

    test "lists all sessions", %{conn: conn, session: session} do
      {:ok, _index_live, html} = live(conn, ~p"/sessions/#{session.character_id}")

      assert html =~ "Historical Sessions"
    end
  end

  describe "Show" do
    setup [:create_session]

    test "displays session", %{conn: conn, session: session, login: login, logout: logout} do
      {:ok, _show_live, html} = live(conn, ~p"/sessions/#{session.character_id}/show?login=#{login}&logout=#{logout}")

      assert html =~ "Aggregate Stats"
      assert html =~ "Event Feed"
    end
  end
end
