defmodule CAI.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CAI.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias CAI.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import CAI.DataCase
    end
  end

  setup tags do
    CAI.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(CAI.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Insert 3 Death events and their corresponding "Kill Player" GEs for the given character_id, where the first 2 are
  kills and the last is a death.
  """
  def insert_kills(character_id, base_timestamp) do
    deaths = [
      %{
        character_id: 5_429_413_765_549_775_185,
        timestamp: base_timestamp,
        attacker_character_id: character_id,
        attacker_fire_mode_id: 70_019,
        attacker_loadout_id: 6,
        attacker_team_id: 2,
        attacker_vehicle_id: 0,
        attacker_weapon_id: 803_699,
        character_loadout_id: 32,
        is_critical: false,
        is_headshot: false,
        team_id: 2,
        world_id: 13,
        zone_id: 4
      },
      %{
        character_id: 8_279_743_051_027_650_625,
        timestamp: base_timestamp + 5,
        attacker_character_id: character_id,
        attacker_fire_mode_id: 70_019,
        attacker_loadout_id: 6,
        attacker_team_id: 2,
        attacker_vehicle_id: 0,
        attacker_weapon_id: 803_699,
        character_loadout_id: 15,
        is_critical: false,
        is_headshot: false,
        team_id: 2,
        world_id: 13,
        zone_id: 4
      },
      %{
        character_id: character_id,
        timestamp: base_timestamp + 6,
        attacker_character_id: 5_429_413_765_549_775_185,
        attacker_fire_mode_id: 7572,
        attacker_loadout_id: 20,
        attacker_team_id: 1,
        attacker_vehicle_id: 0,
        attacker_weapon_id: 7274,
        character_loadout_id: 32,
        is_critical: false,
        is_headshot: false,
        team_id: 1,
        world_id: 13,
        zone_id: 4
      }
    ]

    CAI.Repo.insert_all(CAI.ESS.Death, deaths)

    ges = [
      %{
        amount: 100,
        character_id: character_id,
        experience_id: 1,
        loadout_id: 32,
        other_id: 5_429_413_765_549_775_185,
        team_id: 2,
        timestamp: base_timestamp,
        world_id: 13,
        zone_id: 4
      },
      %{
        amount: 100,
        character_id: character_id,
        experience_id: 1,
        loadout_id: 32,
        other_id: 8_279_743_051_027_650_625,
        team_id: 2,
        timestamp: base_timestamp + 5,
        world_id: 13,
        zone_id: 4
      },
      %{
        amount: 100,
        character_id: 5_429_413_765_549_775_185,
        experience_id: 1,
        loadout_id: 20,
        other_id: character_id,
        team_id: 1,
        timestamp: base_timestamp + 6,
        world_id: 13,
        zone_id: 4
      }
    ]

    CAI.Repo.insert_all(CAI.ESS.GainExperience, ges)
  end
end
