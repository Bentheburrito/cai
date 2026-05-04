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

  def static_data_interval_hours, do: 24
end
