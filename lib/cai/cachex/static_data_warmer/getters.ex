defmodule CAI.Cachex.StaticDataWarmer.Getters do
  @moduledoc """
  A module for fetching large quantities of mostly-static data from the Census/Community GitHub.

  ## TODO:

  need to find a better data source for vehicle costs than vehicle_cost_logo_map...
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

        cost_map = vehicle_cost_logo_map()

        vehicle_map =
          for vehicle <- res_map["vehicle_list"], into: %{} do
            {cost, logo_path} = cost_map[vehicle["vehicle_id"]] || {0, nil}

            {{:vehicle, maybe_to_int(vehicle["vehicle_id"])},
             %{
               "name" => vehicle["name"]["en"],
               "description" => vehicle["description"]["en"],
               "cost" => cost,
               "currency_id" => vehicle["cost_resource_id"],
               "image_path" => vehicle["image_path"],
               "logo_path" => logo_path,
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

  defp vehicle_cost_logo_map do
    %{
      "2009" => {0, nil},
      "7" => {350, PS2.API.get_image_url("/files/ps2/images/static/77944.png")},
      "2128" => {0, nil},
      "14" => {250, PS2.API.get_image_url("/files/ps2/images/static/79813.png")},
      "8" => {350, PS2.API.get_image_url("/files/ps2/images/static/77941.png")},
      "2123" => {0, PS2.API.get_image_url("/files/ps2/images/static/77941.png")},
      "101" => {0, nil},
      "5" => {450, PS2.API.get_image_url("/files/ps2/images/static/77943.png")},
      "6" => {450, PS2.API.get_image_url("/files/ps2/images/static/77939.png")},
      "100" => {0, nil},
      "2010" => {50, PS2.API.get_image_url("/files/ps2/images/static/77940.png")},
      "2124" => {350, PS2.API.get_image_url("/files/ps2/images/static/77944.png")},
      "2039" => {200, PS2.API.get_image_url("/files/ps2/images/static/84728.png")},
      "2040" => {0, PS2.API.get_image_url("/files/ps2/images/static/79813.png")},
      "3" => {350, PS2.API.get_image_url("/files/ps2/images/static/77936.png")},
      "161" => {0, nil},
      "163" => {0, nil},
      "160" => {0, nil},
      "2033" => {10, nil},
      "15" => {200, PS2.API.get_image_url("/files/ps2/images/static/84728.png")},
      "2122" => {0, PS2.API.get_image_url("/files/ps2/images/static/77938.png")},
      "150" => {0, nil},
      "12" => {150, PS2.API.get_image_url("/files/ps2/images/static/77934.png")},
      "104" => {0, nil},
      "2007" => {1_000_000, nil},
      "0" => {0, nil},
      "2021" => {0, nil},
      "11" => {450, PS2.API.get_image_url("/files/ps2/images/static/77933.png")},
      "10" => {450, PS2.API.get_image_url("/files/ps2/images/static/77935.png")},
      "2036" => {0, nil},
      "151" => {0, nil},
      "1012" => {0, nil},
      "2019" => {1_000_000, nil},
      "105" => {0, nil},
      "2006" => {0, nil},
      "102" => {0, nil},
      "2" => {200, PS2.API.get_image_url("/files/ps2/images/static/77942.png")},
      "2011" => {0, nil},
      "162" => {0, nil},
      "2008" => {0, nil},
      "4" => {450, PS2.API.get_image_url("/files/ps2/images/static/77937.png")},
      "1013" => {0, nil},
      "13" => {0, nil},
      "9" => {350, PS2.API.get_image_url("/files/ps2/images/static/77938.png")},
      "103" => {0, nil},
      "1" => {50, PS2.API.get_image_url("/files/ps2/images/static/77940.png")},
      "2125" => {100, nil},
      "2130" => {200, PS2.API.get_image_url("/files/ps2/images/static/77942.png")},
      "2131" => {450, PS2.API.get_image_url("/files/ps2/images/static/77933.png")},
      "2132" => {250, PS2.API.get_image_url("/files/ps2/images/static/79813.png")},
      "2133" => {450, PS2.API.get_image_url("/files/ps2/images/static/77937.png")},
      "2134" => {450, PS2.API.get_image_url("/files/ps2/images/static/77943.png")},
      "2135" => {450, PS2.API.get_image_url("/files/ps2/images/static/77939.png")},
      "2136" => {350, PS2.API.get_image_url("/files/ps2/images/static/39607.png")},
      "2137" => {450, "/images/93604.png"},
      "2139" => {200, PS2.API.get_image_url("/files/ps2/images/static/77942.png")},
      "2140" => {450, PS2.API.get_image_url("/files/ps2/images/static/77933.png")},
      "2141" => {250, PS2.API.get_image_url("/files/ps2/images/static/79813.png")}
    }
  end
end
