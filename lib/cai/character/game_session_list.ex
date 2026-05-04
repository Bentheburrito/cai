defmodule CAI.Character.GameSessionList do
  @moduledoc """
  A Projector for a particular character's PS2 sessions. This projector is
  powered by the GameSession projector, and its main function is to create a
  new GameSession after the current one is marked `status: :logged_out | :timed_out`.
  """

  import CAI.Guards

  alias CAI.Character.GameSession

  @derive JSON.Encoder
  @enforce_keys ~w|character_id|a
  defstruct character_id: nil, sessions: []

  def keys(event) do
    for {_, id} <- Map.take(event, [:character_id, :other_id, :attacker_character_id]),
        is_character_id(id),
        into: MapSet.new(),
        do: id
  end

  def init(character_id), do: struct!(__MODULE__, character_id: character_id, sessions: [])

  def pubsub_keys(%__MODULE__{sessions: [%GameSession{world_id: world_id}]}) when is_integer(world_id),
    do: [CAI.PubSub.world_event(world_id)]

  def pubsub_keys(%__MODULE__{}), do: []

  # no session history - just create a new one
  def handle_event(%__MODULE__{sessions: []} = state, event) do
    session = GameSession.init(state.character_id, event)
    struct!(state, sessions: [session])
  end

  # apply event to ongoing session
  def handle_event(%__MODULE__{sessions: [%GameSession{status: :in_progress} = session | done]} = state, event) do
    case GameSession.handle_event(session, event) do
      %GameSession{status: status} = session when status in [:in_progress, :logged_out] ->
        struct!(state, sessions: [session | done])

      # timed_out is a special case: the session that timed out didn't actually
      # apply the event, because it belongs to another session that we need to create
      %GameSession{status: :timed_out} = session ->
        struct!(state, sessions: [GameSession.init(state.character_id, event), session | done])
    end
  end

  # session finished - start a new session to apply the event to
  def handle_event(%__MODULE__{sessions: [%GameSession{status: :logged_out} | _] = done} = state, event) do
    struct!(state, sessions: [GameSession.init(state.character_id, event) | done])
  end

  def load(attrs) do
    struct(__MODULE__,
      character_id: Map.fetch!(attrs, "character_id"),
      sessions: Enum.map(attrs["sessions"], &GameSession.load/1)
    )
  end
end
