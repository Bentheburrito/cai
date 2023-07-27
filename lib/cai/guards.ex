defmodule CAI.Guards do
  @moduledoc """
  Guards and conditional functions
  """

  require CAI.Guards

  import Bitwise

  @xp_guard_data_path "./guard_data/xp.pairs"
  def xp_guard_data_path, do: @xp_guard_data_path

  @doc """
  Character IDs are always odd.

  https://discord.com/channels/251073753759481856/451032574538547201/1089955112216170496
  """
  defguard is_character_id(id) when is_integer(id) and (1 &&& id) == 1

  @doc """
  NPC IDs are always even.

  https://discord.com/channels/251073753759481856/451032574538547201/1089955112216170496
  """
  defguard is_npc_id(id) when is_integer(id) and (1 &&& id) == 0

  def character_id?(id), do: is_character_id(id)
  def npc_id?(id), do: is_npc_id(id)

  # An unfortunately hacky workaround to getting {experience_id, xp_description} pairs at compile-time so we can define
  # these XP guards.
  xp_pairs =
    case File.read(@xp_guard_data_path) do
      {:ok, contents} ->
        contents
        |> String.split("|||", trim: true)
        |> Stream.chunk_every(2)
        |> Enum.map(fn [id, desc] -> {String.to_integer(id), desc} end)

      {:error, error} ->
        error = inspect(error)
        raise "Unable to read file #{@xp_guard_data_path}: #{inspect(error)}"
    end

  kill_xp_filter = fn {_id, desc} ->
    desc = String.downcase(desc)
    (String.contains?(desc, "kill") or String.contains?(desc, "headshot")) and not String.contains?(desc, "assist")
  end

  @kill_xp xp_pairs |> Stream.filter(kill_xp_filter) |> Enum.map(fn {id, _} -> id end)
  defguard is_kill_xp(id) when id in @kill_xp

  assist_xp_filter = fn {_id, desc} ->
    desc
    |> String.downcase()
    |> String.contains?("assist")
  end

  @assist_xp xp_pairs |> Stream.filter(assist_xp_filter) |> Enum.map(fn {id, _} -> id end)
  defguard is_assist_xp(id) when id in @assist_xp

  gunner_assist_xp_filter = fn {_id, desc} ->
    desc = String.downcase(desc)

    String.contains?(desc, "kill by") and
      not String.contains?(desc, ["hive xp", "squad member"])
  end

  @gunner_assist_xp xp_pairs |> Stream.filter(gunner_assist_xp_filter) |> Enum.map(fn {id, _} -> id end)
  defguard is_gunner_assist_xp(id) when id in @gunner_assist_xp

  defguard is_revive_xp(id) when id in [7, 53]
end
