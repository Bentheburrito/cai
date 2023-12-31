defmodule CAIWeb.SessionLive.Show.Model do
  @moduledoc """
  A struct to hold assigns and helper functions for modifications for SessionLive.Show
  """

  import LiveModel

  alias CAI.Characters.{Character, Session}
  alias CAIWeb.SessionLive.Blurbs
  alias CAIWeb.SessionLive.Entry

  defmodel do
    field :aggregates, map(), default: Session.take_aggregates()
    field :blurbs, {:enabled, Blurbs.t()} | :disabled, default: :disabled
    field :character, Character.t()
    field :duration_mins, integer(), default: 0
    field :events_limit, integer(), default: 15
    field :last_entry, Entry.t()
    field :live?, boolean(), default: false
    field :loading_more?, boolean(), default: false
    field :page_title, String.t(), default: "Character Session"
    field :pending_groups, map(), default: %{}
    field :pending_queries, map(), default: %{}
    field :remaining_events, list(), default: []
    field :world_id, integer()
    field :login, integer(), required: true
    field :logout, integer(), required: true
  end
end
