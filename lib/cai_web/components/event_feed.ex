defmodule CAIWeb.EventFeed do
  @moduledoc """
  The Event Feed found on SessionLive.Show
  """

  use Phoenix.Component

  import CAIWeb.CoreComponents
  import CAIWeb.EventFeed.Components

  attr :entry_stream, Phoenix.LiveView.LiveStream, required: true
  attr :loading_more?, :boolean, required: true
  attr :more_events?, :boolean, required: true
  slot :inner_block

  def event_feed(assigns) do
    ~H"""
    <div>
      <h3 class="m-2">
        <%= render_slot(@inner_block) %>
      </h3>
      <div class="border-solid border-4 m-1 p-2 rounded-2xl border-gray-400">
        <span id="live-event-feed" phx-update="stream">
          <.entry :for={{dom_id, entry} <- @entry_stream} entry={entry} id={dom_id} />
        </span>
        <%!-- pattern matching against empty list, since `length/1` is O(n) --%>
        <span :if={@more_events?} class="flex justify-center">
          <%= if @loading_more? do %>
            <.button
              id="load-more-button"
              phx-click="load-more-events"
              class="absolute mx-auto border-solid border-2 border-gray-400 hover:bg-zinc-900 text-gray-400 active:text-gray-400"
              disabled
            >
              Loading...
            </.button>
          <% else %>
            <.button
              id="load-more-button"
              phx-click="load-more-events"
              class="absolute mx-auto border-solid border-2 border-gray-400"
            >
              Load More
            </.button>
          <% end %>
        </span>
      </div>
    </div>
    """
  end
end
