-- Empty collections must preserve whether their element type is known.
DO $$
DECLARE
  c collection;
  ic icollection;
  c2 collection;
  ic2 icollection;
  a integer[];
  bad text;
  rejected boolean;
BEGIN
  c := '{}'::collection;
  ic := '{}'::icollection;
  ASSERT value_type(c) IS NULL AND value_type(ic) IS NULL;
  ASSERT c::text = '{}' AND ic::text = '{}';
  c2 := c::text::collection;
  ic2 := ic::text::icollection;
  ASSERT count(c2) = 0 AND count(ic2) = 0;
  ASSERT value_type(c2) IS NULL AND value_type(ic2) IS NULL;

  c := '{"value_type":"integer","entries":{}}'::collection;
  ic := '{"value_type":"integer","entries":{}}'::icollection;
  ASSERT value_type(c) = 'integer'::regtype;
  ASSERT value_type(ic) = 'integer'::regtype;
  ASSERT c::text::jsonb = '{"value_type":"integer","entries":{}}'::jsonb;
  ASSERT ic::text::jsonb = '{"value_type":"integer","entries":{}}'::jsonb;
  c2 := c::text::collection;
  ic2 := ic::text::icollection;
  ASSERT count(c2) = 0 AND count(ic2) = 0;
  ASSERT value_type(c2) = 'integer'::regtype;
  ASSERT value_type(ic2) = 'integer'::regtype;

  ic := to_icollection(ARRAY[]::integer[]);
  ASSERT value_type(ic) = 'integer'::regtype;
  a := to_array(ic, NULL::integer);
  ASSERT cardinality(a) = 0;

  c := delete(add(NULL::collection, 'key', 42));
  ic := delete(add(NULL::icollection, 1, 42));
  ASSERT value_type(c) = 'integer'::regtype;
  ASSERT value_type(ic) = 'integer'::regtype;

  -- A bare empty object is valid; incomplete envelopes and invalid types are not.
  FOREACH bad IN ARRAY ARRAY[
    '{"value_type":"integer"}',
    '{"value_type":null}',
    '{"value_type":null,"entries":{}}',
    '{"value_type":23,"entries":{}}',
    '{"entries":"invalid"}'
  ] LOOP
    rejected := false;
    BEGIN
      c2 := bad::collection;
    EXCEPTION WHEN invalid_text_representation OR internal_error THEN
      rejected := true;
    END;
    ASSERT rejected, 'malformed collection input must be rejected';

    rejected := false;
    BEGIN
      ic2 := bad::icollection;
    EXCEPTION WHEN invalid_text_representation OR internal_error THEN
      rejected := true;
    END;
    ASSERT rejected, 'malformed icollection input must be rejected';
  END LOOP;
END $$;

CREATE TEMP TABLE empty_type_storage (c collection, ic icollection);
INSERT INTO empty_type_storage VALUES
  ('{}'::collection, '{}'::icollection),
  ('{"value_type":"integer","entries":{}}'::collection,
   '{"value_type":"integer","entries":{}}'::icollection),
  (delete(add(NULL::collection, 'key', 42)),
   delete(add(NULL::icollection, 1, 42)));

DO $$
DECLARE
  c collection;
  ic icollection;
BEGIN
  SELECT s.c, s.ic INTO c, ic
    FROM empty_type_storage AS s
   WHERE value_type(s.c) IS NULL;
  ASSERT value_type(c) IS NULL AND value_type(ic) IS NULL;
  ASSERT c::text = '{}' AND ic::text = '{}';

  SELECT s.c, s.ic INTO c, ic
    FROM empty_type_storage AS s
   WHERE value_type(s.c) = 'integer'::regtype
   ORDER BY s.c::text
   LIMIT 1;
  ASSERT value_type(c) = 'integer'::regtype;
  ASSERT value_type(ic) = 'integer'::regtype;
END $$;

DROP TABLE empty_type_storage;
