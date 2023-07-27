defmodule CAI.Cachex do
  @moduledoc """
  Configuration for Cachex caches.
  """

  ### Cache Names ###
  def characters, do: :characters
  def character_names, do: :character_names
  def static_data, do: :static_data
  def facilities, do: :facilities
  def outfits, do: :outfits

  def dump_path, do: System.get_env("CACHEX_DUMP_PATH", "./cache/static.data")

  def static_data_interval_hours, do: 12
end
