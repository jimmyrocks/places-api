CREATE OR REPLACE FUNCTION public.nps_node_o2p_calculate_zorder(text)
  RETURNS integer AS
$BODY$
DECLARE
  v_tag ALIAS for $1;
  v_zorder integer;
BEGIN

SELECT
  CASE
    WHEN v_tag = 'Visitor Center' THEN 40
    WHEN v_tag = 'Ranger Station' THEN 38
    WHEN v_tag = 'Information' THEN 36
    WHEN v_tag = 'Lodge' THEN 34
    WHEN v_tag = 'Campground' THEN 32
    WHEN v_tag = 'Food Service' THEN 30
    WHEN v_tag = 'Store' THEN 28
    WHEN v_tag = 'Picnic Site' THEN 26
    WHEN v_tag = 'Picnic Table' THEN 26
    WHEN v_tag = 'Trailhead' THEN 24
    WHEN v_tag = 'Car Parking' THEN 22
    WHEN v_tag = 'Restrooms' THEN 20
    ELSE 0
  END AS order
INTO
  v_zorder;

RETURN v_zorder;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION public.nps_node_o2p_calculate_zorder(text)
  OWNER TO postgres;
  ------------
  
  -----
-- Convert JSON to hstore
CREATE OR REPLACE FUNCTION public.json_to_hstore(
  json
)
  RETURNS hstore AS $json_to_hstore$
DECLARE
  v_json ALIAS for $1;
  v_hstore HSTORE;
BEGIN
SELECT
  hstore(array_agg(key), array_agg(value))
FROM
 json_each_text(v_json)
INTO
  v_hstore;

 RETURN v_hstore;
END;
$json_to_hstore$
LANGUAGE plpgsql;
  
--
-- probably can replace the one below it, this one just as an all option, where the other one doesn't
CREATE OR REPLACE FUNCTION public.o2p_get_name(
  hstore,
  character(1),
  boolean
)
  RETURNS text AS $o2p_get_name$
DECLARE
  v_hstore ALIAS for $1;
  v_member_type ALIAS FOR $2; -- Current not used, update this!
  v_all ALIAS for $3;
  v_name TEXT;
BEGIN

SELECT
  name
FROM (
  SELECT
    name,
    max(hstore_len) hstore_len,
    count(*) match_count
  FROM (
    SELECT
      name,
      available_tags,
      each(v_hstore) input_tags,
      hstore_len
    FROM (
      SELECT
        name,
        each(tags) available_tags,
        hstore_len
      FROM (
        SELECT
          name, 
          delete(json_to_hstore(tags), 'nps:fcat') tags,
          array_length(%% (delete(json_to_hstore(tags), 'nps:fcat')),1)/2 hstore_len
        FROM
          tag_list
        WHERE
          tag_list.geometry @> ARRAY['point'] AND
          (v_all OR (
            tag_list.searchable is null OR
            tag_list.searchable is true
          ))
      ) available_tags
    ) explode_tags
  ) paired_tags
  WHERE
    available_tags = input_tags
  GROUP BY name
  ) counted_tags
WHERE
  hstore_len = match_count
ORDER BY
  match_count DESC
LIMIT
  1
INTO
  v_name;

 RETURN v_name;
END;
$o2p_get_name$
LANGUAGE plpgsql;
----
  
-- DROP FUNCTION o2p_get_name(hstore, character(1));
CREATE OR REPLACE FUNCTION public.o2p_get_name(
  hstore,
  character(1)
)
  RETURNS text AS $o2p_get_name$
DECLARE
  v_hstore ALIAS for $1;
  v_member_type ALIAS FOR $2; -- Current not used, update this!
  v_name TEXT;
BEGIN

SELECT
  name
FROM (
  SELECT
    name,
    max(hstore_len) hstore_len,
    count(*) match_count
  FROM (
    SELECT
      name,
      available_tags,
      each(v_hstore) input_tags,
      hstore_len
    FROM (
      SELECT
        name,
        each(tags) available_tags,
        hstore_len
      FROM (
        SELECT
          name, 
          delete(json_to_hstore(tags), 'nps:fcat') tags,
          array_length(%% (delete(json_to_hstore(tags), 'nps:fcat')),1)/2 hstore_len
        FROM
          tag_list
        WHERE
          tag_list.geometry @> ARRAY['point'] AND
          tag_list.searchable is null or tag_list.searchable is true
      ) available_tags
    ) explode_tags
  ) paired_tags
  WHERE
    available_tags = input_tags
  GROUP BY name
  ) counted_tags
WHERE
  hstore_len = match_count
ORDER BY
  match_count DESC
LIMIT
  1
INTO
  v_name;

 RETURN v_name;
END;
$o2p_get_name$
LANGUAGE plpgsql;

-------------


CREATE OR REPLACE VIEW public.nps_planet_osm_point_view AS 
SELECT
  osm_id, "name", "fcat", "tags", "created", "way", nps_node_o2p_calculate_zorder(fcat) as z_order
FROM (
  SELECT
    nodes.id AS osm_id,
    nodes.tags -> 'name'::text AS "name",
    o2p_get_name(tags, 'N') AS "fcat",
    tags AS "tags",
    NOW()::timestamp without time zone AS created,
    st_transform(nodes.geom, 900913) AS way
  FROM
    nodes
  WHERE
    nodes.tags <> ''::hstore AND 
    nodes.tags IS NOT NULL
) base
WHERE
  fcat IS NOT NULL;
  
------------------

-- Function: public.nps_pgs_update_o2p(bigint, character)

-- DROP FUNCTION public.nps_pgs_update_o2p(bigint, character);

CREATE OR REPLACE FUNCTION public.nps_pgs_update_o2p(bigint, character)
  RETURNS boolean AS
$BODY$
  DECLARE
    v_id ALIAS FOR $1;
    v_member_type ALIAS FOR $2;
    v_rel_id BIGINT;
  BEGIN
    -- Update this object in the nps o2p tables
        IF v_member_type = 'N' THEN
          DELETE FROM planet_osm_point WHERE osm_id = v_id;
          INSERT INTO planet_osm_point (
            SELECT * FROM nps_planet_osm_point_view where osm_id = v_id
          );
    END IF;

  RETURN true;
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION public.nps_pgs_update_o2p(bigint, character)
  OWNER TO osm;
