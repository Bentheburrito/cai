defmodule CAI.Scripts do
  @moduledoc """
  A module for fetching large quantities of mostly-static data from the Census and caching it locally as JSON.

  ## TODO:

  Post-MVP, I think this module should be replaced by Cachex caches, using the `dump/2` and `load/2` fns
  to persist them to disk (in the case of an application/VM restart). Could also schedule jobs (Oban?) to pull
  the data from the Census/Community GitHub if PS2 a maintainance/update is detected (Isn't there an RSS feed
  for this? GitHub hook to detect when community GH has changes merged in??)

  If this project ever goes multi-node, though, persisting to disk could probably be avoid (or at least a last
  resort), as new nodes joining the cluster can sync to get cache states.
  """

  import PS2.API.QueryBuilder

  alias PS2.API.{Query, QueryResult, Tree}

  def get_and_dump_weapons do
    # Get weapon info with sanctions
    res =
      HTTPoison.get!(
        "https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Weapons/sanction-list.csv"
      )

    [_headers | lines] = String.split(res.body, "\n")

    # Get weapon image info

    # default to an id/path that doesn't exist, so the `onerror` attribute in the template can take over
    default_image_info = %{"image_id" => -1, "image_path" => ""}

    weapon_image_infos =
      lines
      |> Stream.map(&(&1 |> String.split(",") |> List.first()))
      |> Stream.chunk_every(800)
      |> Stream.map(fn item_ids ->
        {:ok, %QueryResult{data: item_images}} =
          Query.new(collection: "item")
          |> term("item_id", Enum.join(item_ids, ","))
          |> limit(9000)
          |> show(["item_id", "image_id", "image_path"])
          |> tree(Tree.new(field: "item_id"))
          |> PS2.API.query_one(CAI.sid())

        item_images
      end)
      |> Enum.reduce(&Map.merge(&1, &2))
      |> Stream.filter(fn {_key, value} -> value != "-" end)
      |> Stream.map(fn {item_id, images} ->
        {item_id, Map.update!(images, "image_id", &maybe_to_int(&1))}
      end)
      |> Enum.into(%{})

    weapon_map =
      for line <- lines, into: %{} do
        [item_id, category, is_vehicle_weapon, item_name, faction_id, sanction] = String.split(line, ",")

        # Replace excessive quotation
        item_name =
          item_name
          # completely remove single "'s
          |> String.replace(~r/(.?)"(.?)/, "\\1\\2", global: true)
          # condense consecutive "'s to one "
          |> String.replace(~r/(?:"){2,}/, "\"", global: true)

        weapon_info = %{
          "category" => category,
          "vehicle_weapon?" => is_vehicle_weapon == "1",
          "name" => item_name,
          "faction_id" => (String.length(faction_id) > 0 && String.to_integer(faction_id)) || 0,
          "sanction" => sanction
        }

        image_info = Map.get(weapon_image_infos, item_id, default_image_info)

        full_weapon_info = Map.merge(weapon_info, image_info)

        {item_id, full_weapon_info}
      end

    File.write(
      "./cache/weapons.json",
      Jason.encode!(weapon_map, pretty: true)
    )
  end

  def get_and_dump_vehicles do
    res =
      HTTPoison.get!("https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Census/vehicle.json")

    res_map = Jason.decode!(res.body)

    cost_map = File.read!("./cache/vehicle_cost_map.json") |> Jason.decode!()

    vehicle_map =
      for vehicle <- res_map["vehicle_list"], into: %{} do
        cost = cost_map[vehicle["vehicle_id"]] || 0

        {vehicle["vehicle_id"],
         %{
           "name" => vehicle["name"]["en"],
           "description" => vehicle["description"]["en"],
           "cost" => cost,
           "currency_id" => vehicle["cost_resource_id"],
           "image_path" => vehicle["image_path"],
           "type_id" => vehicle["type_id"]
         }}
      end

    File.write("./cache/vehicles.json", Jason.encode!(vehicle_map, pretty: true))
  end

  def get_and_dump_xp do
    to_int_or_float = fn string ->
      case Integer.parse(string) do
        {_num, "." <> _rest} -> String.to_float(string)
        {num, _rest} -> num
        :error -> 0
      end
    end

    {:ok, %PS2.API.QueryResult{data: xp_list}} =
      PS2.API.query(Query.new(collection: "experience") |> limit(5000), CAI.sid())

    new_xp_map =
      for %{"description" => desc} = xp_map <- xp_list,
          not String.contains?(desc, "HIVE"),
          into: %{} do
        xp_map
        |> Map.update("xp", 0, to_int_or_float)
        |> Map.pop!("experience_id")
      end
      |> Jason.encode!(pretty: true)

    File.write("./cache/xp.json", new_xp_map)
  end

  def get_and_dump_facilities do
    res =
      HTTPoison.get!(
        "https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Census/map_region.json"
      )

    res_map = Jason.decode!(res.body)

    facility_map =
      for facility <- res_map["map_region_list"], into: %{} do
        {facility["facility_id"],
         Map.new(facility, fn {field_name, value} ->
           {field_name, maybe_to_int(value)}
         end)}
      end

    File.write(
      "./cache/facilities.json",
      Jason.encode!(facility_map, pretty: true)
    )
  end

  def load_static_file(path) do
    unless File.exists?(path) do
      get_and_dump_facilities()
      get_and_dump_vehicles()
      get_and_dump_weapons()
      get_and_dump_xp()
    end

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.new(fn {str_key, value} -> {maybe_to_int(str_key), value} end)
  end

  defp maybe_to_int(value, default \\ :use_value)

  defp maybe_to_int(value, _default) when is_integer(value), do: value

  defp maybe_to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, _rest} -> int_value
      :error -> if default == :use_value, do: value, else: default
    end
  end

  defp maybe_to_int(value, default) do
    if default == :use_value, do: value, else: default
  end
end
