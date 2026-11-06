-- Text input/output must preserve keys, values, NULLs and the element type.
-- Include both expanded values and values flattened by table storage.

-- JSON escaping, insertion order and the full bigint key range.
DO $$
DECLARE
  c collection;
  ic icollection;
  s text := E'quote " slash \\ newline\n tab\t';
BEGIN
  c := add(add(add(c, s, s), 'empty', ''), 'null', NULL::text);
  ic := add(add(add(ic, '-9223372036854775808'::bigint, s),
                0, ''), '9223372036854775807'::bigint, NULL::text);
  ASSERT c::text::jsonb = jsonb_build_object('value_type', 'pg_catalog.text',
      'entries', jsonb_build_object(s, s, 'empty', '', 'null', NULL));
  ASSERT ic::text::jsonb = jsonb_build_object('value_type', 'pg_catalog.text',
      'entries', jsonb_build_object('-9223372036854775808', s,
                                   '0', '', '9223372036854775807', NULL));
  c := c::text::collection;
  ic := ic::text::icollection;
  ASSERT count(c) = 3 AND count(ic) = 3;
  ASSERT find(c, s) = s AND find(ic, '-9223372036854775808'::bigint) = s;
  ASSERT find(c, 'empty') = '' AND find(ic, 0) = '';
  ASSERT exist(c, 'null') AND find(c, 'null') IS NULL;
  ASSERT exist(ic, '9223372036854775807'::bigint)
         AND find(ic, '9223372036854775807'::bigint) IS NULL;
  ASSERT first_key(c) = s AND first_key(ic) = '-9223372036854775808'::bigint;
  ASSERT last_key(c) = 'null' AND last_key(ic) = '9223372036854775807'::bigint;
END $$;

-- Only bare {} is untyped; an envelope without value_type defaults to text.
SELECT '{}'::collection, '{}'::icollection;
SELECT value_type('{}'::collection), value_type('{}'::icollection);
SELECT value_type('{"entries":{}}'::collection),
       value_type('{"entries":{}}'::icollection);
SELECT value_type(add('{}'::collection, '1', 42)),
       value_type(add('{}'::icollection, 1, 42));
SELECT value_type('{}'::collection('integer')),
       value_type('{}'::icollection('integer'));

CREATE TABLE io_empty (label text, c collection, ic icollection);
INSERT INTO io_empty VALUES
  ('untyped', '{}'::collection, '{}'::icollection),
  ('null source', delete(NULL::collection), delete(NULL::icollection)),
  ('typed', '{"value_type":"integer","entries":{}}'::collection,
            '{"value_type":"integer","entries":{}}'::icollection),
  ('deleted', delete(add(NULL::collection, '1', 42)),
              delete(add(NULL::icollection, 1, 42))),
  ('array', '{}'::collection('integer'), to_icollection(ARRAY[]::integer[]));
SELECT label, c, ic, value_type(c), value_type(ic) FROM io_empty ORDER BY label;
SELECT label, c::text::collection::text = c::text AS collection_roundtrip,
       ic::text::icollection::text = ic::text AS icollection_roundtrip
  FROM io_empty ORDER BY label;
SELECT to_array(to_icollection(ARRAY[]::integer[]), NULL::integer);

-- These input functions need their type I/O parameter and/or typmod = -1.
CREATE SCHEMA io_types;
CREATE TYPE io_types."enum value" AS ENUM ('a"b\\c');
CREATE TYPE io_types.pair AS (n integer, s text);
CREATE DOMAIN io_types.positive AS integer CHECK (VALUE > 0);
CREATE DOMAIN io_types.short_text AS varchar(3);
CREATE DOMAIN io_types.int_array AS integer[];
CREATE DOMAIN io_types.not_null AS integer NOT NULL;
CREATE DOMAIN io_types.check_null AS integer CHECK (VALUE IS NOT NULL);

CREATE TABLE io_values (
  label text, element_type regtype, expected_value text,
  c collection, ic icollection
);
INSERT INTO io_values (label, element_type, expected_value) VALUES
  ('text', 'text', E'a"b\\c\nd'),
  ('null', 'text', NULL),
  ('array', 'integer[]', '{1,NULL,3}'),
  ('multidimensional array', 'integer[]', '[0:1][2:3]={{1,2},{3,4}}'),
  ('enum', 'io_types."enum value"', 'a"b\\c'),
  ('composite', 'io_types.pair', '(42,"a,b")'),
  ('numeric', 'numeric', '1234.56789'),
  ('varchar', 'varchar', 'not truncated'),
  ('char', 'bpchar', 'not truncated'),
  ('domain', 'io_types.positive', '7'),
  ('domain null', 'io_types.positive', NULL),
  ('domain typmod', 'io_types.short_text', 'abc'),
  ('domain array', 'io_types.int_array', '{1,NULL,3}'),
  ('not null domain', 'io_types.not_null', '1');
UPDATE io_values
   SET c = json_build_object('value_type', element_type::text,
                             'entries', json_build_object('1', expected_value))::text::collection,
       ic = json_build_object('value_type', element_type::text,
                              'entries', json_build_object('1', expected_value))::text::icollection;

-- Check the actual values and types, not just matching output strings.
SELECT label,
       value_type(c) = element_type AND value_type(ic) = element_type AS types_ok,
       count(c) = 1 AND count(ic) = 1 AS counts_ok,
       find(c, '1') IS NOT DISTINCT FROM expected_value AS collection_value,
       find(ic, 1) IS NOT DISTINCT FROM expected_value AS icollection_value,
       c::text::collection::text = c::text AS collection_roundtrip,
       ic::text::icollection::text = ic::text AS icollection_roundtrip
  FROM io_values ORDER BY label;
SELECT find(c, '1', NULL::integer[]) = ARRAY[1,NULL,3] AS collection_array,
       find(ic, 1, NULL::integer[]) = ARRAY[1,NULL,3] AS icollection_array
  FROM io_values WHERE label = 'array';
SELECT (find(c, '1', NULL::io_types.pair)).n AS collection_field,
       (find(ic, 1, NULL::io_types.pair)).n AS icollection_field
  FROM io_values WHERE label = 'composite';

-- COPY exercises both type I/O functions as well as flatten/expand.
CREATE TABLE io_empty_copy (LIKE io_empty);
CREATE TABLE io_values_copy (LIKE io_values);
\copy io_empty TO 'test/results/io_empty.data'
\copy io_empty_copy FROM 'test/results/io_empty.data'
\copy io_values TO 'test/results/io_values.data'
\copy io_values_copy FROM 'test/results/io_values.data'
SELECT count(*) = 5 AS all_empty_rows,
       bool_and(a.c::text = b.c::text AND a.ic::text = b.ic::text) AS values_ok
  FROM io_empty a JOIN io_empty_copy b USING (label);
SELECT count(*) = 14 AS all_value_rows,
       bool_and(value_type(b.c) = a.element_type AND value_type(b.ic) = a.element_type)
         AS types_ok,
       bool_and((find(b.c, '1') IS NOT DISTINCT FROM a.expected_value)
                AND (find(b.ic, 1) IS NOT DISTINCT FROM a.expected_value)) AS values_ok
  FROM io_values a JOIN io_values_copy b USING (label);

-- Domain checks must also be applied to NULL input.
SELECT '{"value_type":"io_types.positive","entries":{"1":"-1"}}'::collection;
SELECT '{"value_type":"io_types.positive","entries":{"1":"-1"}}'::icollection;
SELECT '{"value_type":"io_types.not_null","entries":{"1":null}}'::collection;
SELECT '{"value_type":"io_types.not_null","entries":{"1":null}}'::icollection;
SELECT '{"value_type":"io_types.check_null","entries":{"1":null}}'::collection;
SELECT '{"value_type":"io_types.check_null","entries":{"1":null}}'::icollection;
SELECT '{"value_type":"io_types.short_text","entries":{"1":"long"}}'::collection;
SELECT '{"value_type":"io_types.short_text","entries":{"1":"long"}}'::icollection;

-- Accepting bare {} must not admit incomplete envelopes or invalid types.
SELECT '{"value_type":"integer"}'::collection;
SELECT '{"value_type":"integer"}'::icollection;
SELECT '{"value_type":null,"entries":{}}'::collection;
SELECT '{"value_type":null,"entries":{}}'::icollection;
SELECT '{"value_type":23,"entries":{}}'::collection;
SELECT '{"value_type":23,"entries":{}}'::icollection;
SELECT '{"entries":"invalid"}'::collection;
SELECT '{"entries":"invalid"}'::icollection;

DROP TABLE io_empty_copy, io_values_copy, io_empty, io_values;
DROP DOMAIN io_types.positive, io_types.short_text, io_types.int_array,
            io_types.not_null, io_types.check_null;
DROP TYPE io_types."enum value", io_types.pair;
DROP SCHEMA io_types;
