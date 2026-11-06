-- icollection output must be valid JSON accepted by icollection input.
DO $$
DECLARE
  ic icollection;
  roundtripped icollection;
  value text := E'quote " slash \\ newline\n tab\t';
BEGIN
  ic := add(add(add(NULL::icollection,
                    '-9223372036854775808'::bigint, value),
                0, ''),
            '9223372036854775807'::bigint, NULL::text);

  ASSERT ic::text::jsonb = jsonb_build_object(
      'value_type', 'pg_catalog.text',
      'entries', jsonb_build_object(
          '-9223372036854775808', value,
          '0', '',
          '9223372036854775807', NULL));

  roundtripped := ic::text::icollection;
  ASSERT count(roundtripped) = 3;
  ASSERT find(roundtripped, '-9223372036854775808'::bigint) = value;
  ASSERT find(roundtripped, 0) = '';
  ASSERT exist(roundtripped, '9223372036854775807'::bigint)
         AND find(roundtripped, '9223372036854775807'::bigint) IS NULL;
END $$;
