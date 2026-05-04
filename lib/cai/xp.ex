defmodule CAI.XP do
  import String, only: [contains?: 2]

  @external_resource xp_guard_data_path = Path.join([__DIR__, "xp_id_desc_map.txt"])

  category_checkers = [
    kill: &((contains?(&1, "kill") or contains?(&1, "headshot")) and not contains?(&1, "assist")),
    kill_assist: &contains?(&1, "assist"),
    gunner_assist: &(contains?(&1, "kill by") and not contains?(&1, ["hive xp", "squad member"]))
  ]

  {categories_by_id, ids_by_category} =
    for line <- File.stream!(xp_guard_data_path, [], :line),
        {category, category_checker} <- category_checkers,
        not String.contains?(line, "HIVE XP"),
        reduce: {%{}, %{}} do
      {cats_by_id, ids_by_cat} = acc ->
        [id_str, desc] = String.split(line, " ", parts: 2)
        id = String.to_integer(id_str)

        if category_checker.(String.downcase(desc)) do
          {
            Map.update(cats_by_id, id, MapSet.new([category]), &MapSet.put(&1, category)),
            Map.update(ids_by_cat, category, [id], &[id | &1])
          }
        else
          acc
        end
    end

  @categories_by_id categories_by_id
  def categories_by_id(id), do: Map.fetch(@categories_by_id, id)

  @kill_ids ids_by_category.kill
  defguard is_kill_xp(id) when id in @kill_ids

  @assist_ids ids_by_category.kill_assist
  defguard is_assist_xp(id) when id in @assist_ids

  @gunner_assist_ids ids_by_category.gunner_assist
  defguard is_gunner_assist_xp(id) when id in @gunner_assist_ids

  defguard is_revive_xp(id) when id in [7, 53]

  @dogfighter_xp_ids [331, 332, 333, 1595, 1649]
  defguard is_dogfighter_xp(id) when id in @dogfighter_xp_ids

  @vehicle_destruction_ids [
    24,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    301,
    357,
    501,
    651,
    1449,
    1480,
    1565,
    1594,
    1635,
    1738,
    1804,
    1869,
    1989
  ]
  defguard is_vehicle_destruction_xp(id) when id in @vehicle_destruction_ids

  @vehicle_bonus_xp_ids @dogfighter_xp_ids ++ @vehicle_destruction_ids
  defguard is_vehicle_bonus_xp(id) when id in @vehicle_bonus_xp_ids
  def vehicle_bonus_xp?(id), do: is_vehicle_bonus_xp(id)
end
