defmodule CAI.Cachex.StaticDataWarmer.Getters do
  @moduledoc """
  A module for fetching large quantities of mostly-static data from the Census/Community GitHub.

  ## TODO:

  Schedule jobs (Oban?) to pull static data from the Census/Community GitHub if PS2 a maintainance/update is detected
  (Isn't there an RSS feed for this? GitHub hook to detect when community GH has changes merged in??)

  If this project ever goes multi-node, though, persisting to disk could probably be avoid (or at least a last
  resort), as new nodes joining the cluster can sync to get cache states.

  also need to find a better data source for vehicle costs than vehicle_cost_map...
  """

  import PS2.API.QueryBuilder

  alias PS2.API.{Query, QueryResult, Tree}

  require Logger

  @weapons_url "https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Weapons/sanction-list.csv"
  def get_weapons do
    # Get weapon info with sanctions
    case HTTPoison.get(@weapons_url) do
      {:ok, res} ->
        [_headers | lines] = String.split(res.body, "\n")

        # Get weapon image info

        # default to an id/path that doesn't exist, so the `onerror` attribute in the template can take over
        default_image_info = %{"image_id" => -1, "image_path" => ""}

        weapon_image_infos = fetch_weapon_image_info(lines)

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

            {{:weapon, maybe_to_int(item_id)}, full_weapon_info}
          end

        {:ok, weapon_map}

      error ->
        error
    end
  end

  defp fetch_weapon_image_info(lines) do
    lines
    |> Stream.map(&(&1 |> String.split(",") |> List.first()))
    |> Stream.chunk_every(800)
    |> Stream.map(fn item_ids ->
      Query.new(collection: "item")
      |> term("item_id", Enum.join(item_ids, ","))
      |> limit(9000)
      |> show(["item_id", "image_id", "image_path"])
      |> tree(Tree.new(field: "item_id"))
      |> PS2.API.query_one(CAI.sid())
      |> case do
        {:ok, %QueryResult{data: item_images}} ->
          item_images

        error ->
          Logger.error("Failed to get weapon image chunk data: #{inspect(error)}")
          %{}
      end
    end)
    |> Enum.reduce(&Map.merge(&1, &2))
    |> Stream.filter(fn {_key, value} -> value != "-" end)
    |> Stream.map(fn {item_id, images} ->
      {item_id, Map.update!(images, "image_id", &maybe_to_int(&1))}
    end)
    |> Enum.into(%{})
  end

  @vehicle_url "https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Census/vehicle.json"
  def get_vehicles do
    case HTTPoison.get(@vehicle_url) do
      {:ok, res} ->
        res_map = Jason.decode!(res.body)

        cost_map = vehicle_cost_map()

        vehicle_map =
          for vehicle <- res_map["vehicle_list"], into: %{} do
            cost = cost_map[vehicle["vehicle_id"]] || 0

            {{:vehicle, maybe_to_int(vehicle["vehicle_id"])},
             %{
               "name" => vehicle["name"]["en"],
               "description" => vehicle["description"]["en"],
               "cost" => cost,
               "currency_id" => vehicle["cost_resource_id"],
               "image_path" => vehicle["image_path"],
               "type_id" => vehicle["type_id"]
             }}
          end

        {:ok, vehicle_map}

      error ->
        error
    end
  end

  def get_xp do
    to_int_or_float = fn string ->
      case Integer.parse(string) do
        {_num, "." <> _rest} -> String.to_float(string)
        {num, _rest} -> num
        :error -> 0
      end
    end

    case PS2.API.query(Query.new(collection: "experience") |> limit(5000), CAI.sid()) do
      {:ok, %PS2.API.QueryResult{data: xp_list}} ->
        new_xp_map =
          for %{"description" => desc} = xp_map <- xp_list,
              not String.contains?(desc, "HIVE"),
              into: %{} do
            {xp_id, xp_map} =
              xp_map
              |> Map.update("xp", 0, to_int_or_float)
              |> Map.pop!("experience_id")

            {{:xp, maybe_to_int(xp_id)}, xp_map}
          end

        # Write guard data to a file. If there are new IDs, they should be committed to the repo.
        # This is necessary for GitHub CI.
        content =
          xp_list
          |> Stream.map(fn %{"description" => desc, "experience_id" => id} -> "#{id}|||#{desc}" end)
          |> Enum.sort()
          |> Enum.join("|||")

        File.write!(CAI.Guards.xp_guard_data_path(), content)

        {:ok, new_xp_map}

      error ->
        error
    end
  end

  @facility_url "https://raw.githubusercontent.com/cooltrain7/Planetside-2-API-Tracker/master/Census/map_region.json"
  def get_facilities do
    case HTTPoison.get(@facility_url) do
      {:ok, res} ->
        res_map = Jason.decode!(res.body)

        facility_map =
          for facility <- res_map["map_region_list"], into: %{} do
            {{:facility, maybe_to_int(facility["facility_id"])},
             Map.new(facility, fn {field_name, value} ->
               {field_name, maybe_to_int(value)}
             end)}
          end

        {:ok, facility_map}

      error ->
        error
    end
  end

  defp maybe_to_int(value) when is_integer(value), do: value

  defp maybe_to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, _rest} -> int_value
      :error -> value
    end
  end

  defp maybe_to_int(value), do: value

  defp vehicle_cost_map do
    %{
      "2009" => 0,
      "7" => 350,
      "2128" => 0,
      "14" => 250,
      "8" => 350,
      "2123" => 0,
      "101" => 0,
      "5" => 450,
      "6" => 450,
      "100" => 0,
      "2010" => 50,
      "2124" => 0,
      "2039" => 0,
      "2040" => 0,
      "3" => 350,
      "161" => 0,
      "163" => 0,
      "160" => 0,
      "2033" => 10,
      "15" => 200,
      "2122" => 0,
      "150" => 0,
      "12" => 150,
      "104" => 0,
      "2007" => 1_000_000,
      "0" => 0,
      "2021" => 0,
      "11" => 450,
      "10" => 450,
      "2036" => 0,
      "151" => 0,
      "1012" => 0,
      "2019" => 1_000_000,
      "105" => 0,
      "2006" => 0,
      "102" => 0,
      "2" => 200,
      "2011" => 0,
      "162" => 0,
      "2008" => 0,
      "4" => 450,
      "1013" => 0,
      "13" => 0,
      "9" => 350,
      "103" => 0,
      "1" => 50,
      "2125" => 100
    }
  end
end
