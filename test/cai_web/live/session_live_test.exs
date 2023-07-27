defmodule CAIWeb.SessionLiveTest do
  use CAIWeb.ConnCase

  import Phoenix.LiveViewTest
  import CAI.CharactersFixtures

  alias CAI.Characters.Character

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

  describe "Entry.map/2" do
    alias CAIWeb.SessionLive.Entry
    @koremotsuetr 5_428_491_127_580_230_897

    @tag :regression
    test "will not combine 2 deaths with different weapon IDs" do
      # this bug was observed with KoremotsueTR's session from 7/22/2023 @ 8:53:22 PM to 7/22/2023 @ 9:00:23 PM PST
      character = %Character{character_id: @koremotsuetr}

      # The logic for condensing happens on the last two *mapped* entries, so the end of this list contains an extra
      # 291 (Ribbon Experience) GE event to make sure we hit that logic (this was also an event during the actual
      # session)
      event_history = [
        %CAI.ESS.GainExperience{
          amount: 500,
          character_id: 5_428_440_051_057_603_985,
          experience_id: 593,
          loadout_id: 5,
          other_id: 5_428_491_127_580_230_897,
          team_id: 2,
          timestamp: 1_690_084_788,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.GainExperience{
          amount: 200,
          character_id: 5_428_440_051_057_603_985,
          experience_id: 1,
          loadout_id: 5,
          other_id: 5_428_491_127_580_230_897,
          team_id: 2,
          timestamp: 1_690_084_788,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.Death{
          character_id: 5_428_491_127_580_230_897,
          timestamp: 1_690_084_788,
          attacker_character_id: 5_428_440_051_057_603_985,
          attacker_fire_mode_id: 661,
          attacker_loadout_id: 5,
          attacker_team_id: 2,
          attacker_vehicle_id: 0,
          attacker_weapon_id: 1044,
          character_loadout_id: 8,
          is_critical: false,
          is_headshot: false,
          team_id: 3,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.GainExperience{
          amount: 600,
          character_id: 5_428_440_051_057_603_985,
          experience_id: 279,
          loadout_id: 5,
          other_id: 5_428_491_127_580_230_897,
          team_id: 2,
          timestamp: 1_690_084_760,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.GainExperience{
          amount: 50,
          character_id: 5_428_440_051_057_603_985,
          experience_id: 38,
          loadout_id: 5,
          other_id: 5_428_491_127_580_230_897,
          team_id: 2,
          timestamp: 1_690_084_760,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.GainExperience{
          amount: 500,
          character_id: 5_428_440_051_057_603_985,
          experience_id: 593,
          loadout_id: 5,
          other_id: 5_428_491_127_580_230_897,
          team_id: 2,
          timestamp: 1_690_084_760,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.Death{
          character_id: 5_428_491_127_580_230_897,
          timestamp: 1_690_084_760,
          attacker_character_id: 5_428_440_051_057_603_985,
          attacker_fire_mode_id: 680,
          attacker_loadout_id: 5,
          attacker_team_id: 2,
          attacker_vehicle_id: 0,
          attacker_weapon_id: 880,
          character_loadout_id: 8,
          is_critical: false,
          is_headshot: false,
          team_id: 3,
          world_id: 1,
          zone_id: 2
        },
        %CAI.ESS.GainExperience{
          amount: 500,
          character_id: 5_428_491_127_580_230_897,
          experience_id: 291,
          loadout_id: 8,
          other_id: 0,
          team_id: 3,
          timestamp: 1_690_084_754,
          world_id: 1,
          zone_id: 2
        }
      ]

      entries = Entry.map(event_history, character)

      assert 3 == length(entries)

      assert [
               %Entry{count: 1, event: %CAI.ESS.Death{}, bonuses: bonuses1},
               %Entry{count: 1, event: %CAI.ESS.Death{}, bonuses: bonuses2},
               _ribbon_xp
             ] = entries

      assert 2 == length(bonuses1)
      assert 3 == length(bonuses2)
    end
  end
end
