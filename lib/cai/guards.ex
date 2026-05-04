defmodule CAI.Guards do
  @moduledoc """
  Guards and conditional functions
  """

  import Bitwise

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
end
