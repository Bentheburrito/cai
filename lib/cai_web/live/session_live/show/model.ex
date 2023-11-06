defmodule CAIWeb.SessionLive.Show.Model do
  @moduledoc """
  A struct to hold assigns and helper functions for modifications for SessionLive.Show
  """

  import Phoenix.Component, only: [assign: 3]

  alias CAI.Characters.Session

  @enforce_keys [:login, :logout]
  defstruct aggregates: Map.new(Session.aggregate_fields(), &{&1, 0}),
            blurbs: :disabled,
            character: nil,
            duration_mins: 0,
            events_limit: 15,
            last_entry: nil,
            live?: false,
            loading_more?: false,
            page_title: "Character Session",
            pending_groups: %{},
            pending_queries: %{},
            remaining_events: [],
            world_id: nil,
            login: nil,
            logout: nil

  @doc """
  Create a new Model struct with default values.
  """
  def new(login, logout) do
    %__MODULE__{login: login, logout: logout}
  end

  @doc """
  Updates the model in the assigns of the given `socket`.

  `update_fn` will be called and passed the value under `key`, and the result will replace the original value.
  """
  def update(socket, key, update_fn) when is_function(update_fn) do
    assign(
      socket,
      :model,
      Map.update!(socket.assigns.model, key, update_fn)
    )
  end

  @doc """
  Updates the model in the assigns of the given `socket`.

  The `value` will be put under `key` in the Model, overwriting any existing value.
  """
  def put(socket, key, value) do
    assign(
      socket,
      :model,
      Map.put(socket.assigns.model, key, value)
    )
  end

  @doc """
  Updates the model in the assigns of the given `socket`.

  The values in the given `keyword_list` will overwrite the fields in the model.
  """
  def put(socket, keyword_list) when is_list(keyword_list) do
    assign(
      socket,
      :model,
      Map.merge(socket.assigns.model, Map.new(keyword_list))
    )
  end
end
