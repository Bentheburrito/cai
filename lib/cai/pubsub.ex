defmodule CAI.PubSub do
  alias Phoenix.PubSub
  @pubsub CAI.PubSub

  def subscribe(topic), do: PubSub.subscribe(@pubsub, topic)
  def broadcast(topic, msg), do: PubSub.broadcast(@pubsub, topic, msg)
  def unsubscribe(topic), do: PubSub.unsubscribe(@pubsub, topic)

  def character_event(character_id), do: "event:#{character_id}"
  def world_event(world_id), do: "world_event:#{world_id}"
end
