defmodule CAIWeb.SessionLive.Show.Model do
  import Phoenix.Component, only: [assign: 3]

  alias CAI.Characters.Session
  alias CAIWeb.SessionLive.Show.Model

  @behaviour Access
  defdelegate get(v, key, default), to: Map
  defdelegate fetch(v, key), to: Map
  defdelegate get_and_update(v, key, func), to: Map
  defdelegate pop(v, key), to: Map

  defstruct aggregates: Map.new(Session.aggregate_fields(), &{&1, 0}),
            character: nil,
            events_limit: 15,
            last_entry: nil,
            live?: false,
            loading_more?: false,
            page_title: "Character Session",
            pending_groups: %{},
            remaining_events: [],
            timestamps: nil

  @doc """
  Create a new Model struct with default values.
  """
  def new(), do: %Model{}

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
