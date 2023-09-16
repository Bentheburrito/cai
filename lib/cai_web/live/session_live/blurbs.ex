defmodule CAIWeb.SessionLive.Blurbs do
  @moduledoc """
  A "blurb" is a sound-bite that plays in response to an ESS event.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: CAIWeb.Endpoint,
    router: CAIWeb.Router

  import Phoenix.LiveView

  alias CAIWeb.SessionLive.Show.Model

  alias CAI.ESS.{
    Death,
    GainExperience,
    PlayerLogin,
    PlayerLogout,
    VehicleDestroy
  }

  alias CAIWeb.SessionLive.Blurbs

  require Logger

  @killing_spree_interval_seconds 12

  @voicepacks_path "#{File.cwd!()}/priv/static/audio/voicepacks"
  @voicepacks File.ls!(@voicepacks_path)
  @blurbs (for vp <- @voicepacks,
               category_txt <- File.ls!("#{@voicepacks_path}/#{vp}"),
               String.ends_with?(category_txt, ".txt"),
               reduce: %{} do
             blurbs ->
               content = File.read!("#{@voicepacks_path}/#{vp}/#{category_txt}")
               [_ | _] = filenames = String.split(content, "\n", trim: true)

               category = String.trim_trailing(category_txt, ".txt")
               Map.update(blurbs, vp, %{category => filenames}, &Map.put(&1, category, filenames))
           end)

  def voicepacks, do: @voicepacks

  def track_paths(voicepack) do
    category_map = Map.fetch!(@blurbs, voicepack)

    for {_category, filenames} <- category_map, filename <- filenames, into: MapSet.new() do
      ~p"/audio/voicepacks/#{voicepack}/tracks/#{filename}"
    end
  end

  defstruct killing_spree_count: 0,
            last_kill_timestamp: 0,
            voicepack: "crashmore",
            track_queue: [],
            playing?: false

  def maybe_push_blurb(event, socket) do
    case socket.assigns.model.blurbs do
      {:enabled, %Blurbs{} = state} -> maybe_push_blurb(event, socket, state)
      :disabled -> socket
    end
  end

  def maybe_push_blurb(event, socket, state) do
    character_id = socket.assigns.model.character.character_id

    case fetch_category(event, character_id, state) do
      {:ok, category, state} ->
        # if the track_queue is empty and we're not currently playing anything, play the sound directly.
        # Otherwise, enqueue.
        if match?([], state.track_queue) and not state.playing? do
          case get_random_blurb_filename(category, state) do
            {:ok, track_filename} ->
              socket
              |> push_event("play-blurb", %{"track" => track_filename})
              |> Model.put(:blurbs, {:enabled, %Blurbs{state | playing?: true}})

            :error ->
              socket
          end
        else
          # This may be slow, but it's simple, and I don't forsee an obsurd amount of tracks building up
          # The worst case I can think of is mass-death events from e.g. orbital strikes.
          new_queue = state.track_queue ++ [category]

          new_state = %Blurbs{state | track_queue: new_queue}
          Model.put(socket, :blurbs, {:enabled, new_state})
        end

      :none ->
        socket
    end
  end

  def get_random_blurb_filename(category, %Blurbs{} = state) do
    with filenames <- get_in(@blurbs, [state.voicepack, category]) do
      {:ok, Enum.random(filenames)}
    else
      uhoh ->
        Logger.error("Unable to play blurb: #{inspect(uhoh)}")
        :error
    end
  end

  defp fetch_category(%GainExperience{experience_id: xp_id} = ge, char_id, state)
       when xp_id in [7, 53] do
    cond do
      ge.character_id == char_id -> {:ok, "revive_teammate", state}
      ge.other_id == char_id -> {:ok, "get_revived", state}
      :else -> :none
    end
  end

  defp fetch_category(%Death{character_id: char_id} = death, char_id, state) do
    if char_id == death.attacker_character_id do
      {:ok, "suicide", state}
    else
      {:ok, "death", state}
    end
  end

  defp fetch_category(%Death{attacker_character_id: char_id} = death, char_id, state) do
    timestamp = death.timestamp

    %Blurbs{killing_spree_count: spree_count, last_kill_timestamp: spree_timestamp} = state

    continued_spree? = spree_timestamp > timestamp - @killing_spree_interval_seconds

    {category, new_spree_count} =
      case {spree_count + 1, death.is_headshot, continued_spree?} do
        {_, true, false} -> {"kill_headshot", 1}
        {_, false, false} -> {"kill", 1}
        {2, _, true} -> {"kill_double", spree_count + 1}
        {3, _, true} -> {"kill_triple", spree_count + 1}
        {4, _, true} -> {"kill_quad", spree_count + 1}
        {5, _, true} -> {"kill_penta", spree_count + 1}
        {n, _, true} when n > 5 -> {"kill_penta", spree_count + 1}
      end

    new_session = %Blurbs{
      state
      | killing_spree_count: new_spree_count,
        last_kill_timestamp: timestamp
    }

    {:ok, category, new_session}
  end

  defp fetch_category(%VehicleDestroy{} = vd, char_id, state) do
    cond do
      vd.character_id == char_id and vd.character_id == vd.attacker_character_id ->
        {:ok, "destroy_own_vehicle", state}

      vd.attacker_character_id == char_id ->
        {:ok, "destroy_vehicle", state}

      :else ->
        :none
    end
  end

  defp fetch_category(%PlayerLogin{character_id: char_id}, char_id, state) do
    {:ok, "login", state}
  end

  defp fetch_category(%PlayerLogout{character_id: char_id}, char_id, state) do
    {:ok, "logout", state}
  end

  # defp fetch_category(%ItemAdded{character_id: char_id} = ia, char_id, state) do
  #   cond do
  #     ia.context == "CaptureTheFlag.TakeFlag" ->
  #       {:ok, "ctf_flag_take", state}

  #     ia.context == "GuildBankWithdrawal" && ia.item_id == 6_008_913 ->
  #       {:ok, "bastion_pull", state}

  #     ESS.weapon_id?(ia["item_id"]) ->
  #       {:ok, "unlock_weapon", state}

  #     :else ->
  #       {:ok, "unlock_any", state}
  #   end
  # end

  defp fetch_category(_event, _char_id, _state) do
    :none
  end
end
