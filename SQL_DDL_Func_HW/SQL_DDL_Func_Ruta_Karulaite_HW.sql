/* SQL_DDL_Func_HW — Ruta Karulaite — Tasks 1–5
   PostgreSQL DVD Rental, base tables in public; assignment objects in core.
   Run the ENTIRE file. DDL is committed before the rollback-only tests.
   Prerequisites: restored DVD Rental tables, permission to create schema/index/functions.
   No IDs are hardcoded. Existing incompatible signatures are intentionally NOT dropped:
   CREATE OR REPLACE preserves dependencies and reports incompatible return types.
   Schema/data errors are reported by PostgreSQL; invalid business input uses EXCEPTION.
   Revenue means SUM(payment.amount), attributed by payment_date, not rental_date.
   A film in multiple categories contributes its full revenue to EACH category.
   Supports timestamp and timestamptz source dates. Calendar quarter boundaries
   use the session time zone for timestamptz. Quarter ranges are [start,next_start).
   v2: rollback-only DEFAULT partition fixture supports partitioned payment tables.
   Output rental_date stays a local timestamp for compatibility with the v1 signature.
*/
BEGIN;
CREATE SCHEMA IF NOT EXISTS core;

-- Helper is necessary because LANGUAGE SQL cannot contain RAISE EXCEPTION itself.
-- One YYYY-Qn text parameter represents BOTH year and quarter (e.g. '2007-Q1').
-- Reject malformed input instead of allowing to_date() to normalize invalid quarters.
CREATE OR REPLACE FUNCTION core.quarter_start(p_period text)
RETURNS date LANGUAGE plpgsql IMMUTABLE
SET search_path = pg_catalog
AS $$
BEGIN
    IF p_period IS NULL OR p_period !~ '^[0-9]{4}-Q[1-4]$'
       OR left(p_period, 4) = '0000' THEN
        RAISE EXCEPTION 'Expected YYYY-Q1 through YYYY-Q4; received %', p_period
            USING ERRCODE = '22023';
    END IF;
    RETURN make_date(left(p_period, 4)::integer,
                     (right(p_period, 1)::integer - 1) * 3 + 1, 1);
END;
$$;
COMMENT ON FUNCTION core.quarter_start(text) IS
'Validate one year/quarter parameter and calculate its first calendar date. Invalid/NULL input raises 22023.';

-- TASK 2. Parameter allows historical quarters to be queried without changing data
-- or the server clock. Omitted parameter means this quarter of this year.
-- Validation is a separate first SQL statement: even an empty payment table must
-- reject invalid input. The final SELECT returns rows as required by LANGUAGE SQL.
-- No data => empty result, not a fabricated zero-revenue category.
CREATE OR REPLACE FUNCTION core.get_sales_revenue_by_category_qtr(
    p_period text DEFAULT to_char(CURRENT_DATE, 'YYYY-"Q"Q'))
RETURNS TABLE(category text, total_sales_revenue numeric)
LANGUAGE sql STABLE
SET search_path = pg_catalog
AS $$
    SELECT core.quarter_start(p_period);
    SELECT c.name::text, sum(p.amount)::numeric
    FROM public.payment AS p
    JOIN public.rental AS r ON r.rental_id = p.rental_id
    JOIN public.inventory AS i ON i.inventory_id = r.inventory_id
    JOIN public.film_category AS fc ON fc.film_id = i.film_id
    JOIN public.category AS c ON c.category_id = fc.category_id
    WHERE p.payment_date >= core.quarter_start(p_period)::timestamp
      AND p.payment_date < core.quarter_start(p_period)::timestamp + interval '3 months'
    GROUP BY c.category_id, c.name
    HAVING sum(p.amount) > 0;
$$;
COMMENT ON FUNCTION core.get_sales_revenue_by_category_qtr(text) IS
'Quarterly payment revenue by category. YYYY-Qn parameter defaults to current quarter/year. Invalid quarter raises 22023; absent sales return no rows. Positive group totals exclude zero sales.';

-- TASK 1. to_char(CURRENT_DATE, YYYY-Qn) selects BOTH current year and quarter.
-- This expression is evaluated at query time, so the next quarter is automatic.
-- INNER JOINs only produce categories connected to payments in the selected range;
-- HAVING SUM(amount)>0 additionally removes zero-total categories, even if a zero
-- payment exists. A category with no payments never produces a group.
-- Excluded examples: payment exactly at next quarter start, payment in last year's
-- same quarter, a zero payment without positive sales, a category with no rentals.
-- Historical distributions have old payments (e.g. 2007 or 2017): an empty
-- current view is expected if no current payments have been added. Tests below insert temporary current/boundary/zero payments and compare
-- against an independent aggregation; the transaction is rolled back afterwards.
CREATE OR REPLACE VIEW core.sales_revenue_by_category_qtr AS
SELECT category, total_sales_revenue
FROM core.get_sales_revenue_by_category_qtr();
COMMENT ON VIEW core.sales_revenue_by_category_qtr IS
'Positive payment revenue in the current calendar quarter AND year. Dynamic CURRENT_DATE; excludes categories with no sales or zero totals. Historical DVD Rental normally returns no current rows.';

-- Task 3: Rank films by rental count in each customer's country.
-- Keep all ties and show NULL film details for countries without rentals.
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(p_countries text[])
RETURNS TABLE(country text, film text, rating text, language text,
              length integer, release_year integer)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog
AS $$
BEGIN
    IF p_countries IS NULL OR cardinality(p_countries) = 0 THEN
        RAISE EXCEPTION 'Provide at least one country' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(p_countries) AS n(name)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.country c
            WHERE lower(c.country) = lower(btrim(n.name))
        )
    ) THEN
        RAISE EXCEPTION 'Country list contains an unknown, blank or NULL name'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH requested AS (
        SELECT c.country_id, c.country AS country_name
        FROM public.country c
        WHERE EXISTS (
            SELECT 1
            FROM unnest(p_countries) AS n(name)
            WHERE lower(c.country) = lower(btrim(n.name))
        )
    ), counts AS (
        SELECT q.country_id, i.film_id, count(*) AS rentals
        FROM requested q
        JOIN public.city ci ON ci.country_id = q.country_id
        JOIN public.address a ON a.city_id = ci.city_id
        JOIN public.customer cu ON cu.address_id = a.address_id
        JOIN public.rental r ON r.customer_id = cu.customer_id
        JOIN public.inventory i ON i.inventory_id = r.inventory_id
        GROUP BY q.country_id, i.film_id
    ), ranked AS (
        SELECT counts.*,
               dense_rank() OVER (
                   PARTITION BY counts.country_id ORDER BY counts.rentals DESC
               ) AS popularity
        FROM counts
    )
    SELECT q.country_name::text, f.title::text, f.rating::text,
           btrim(l.name), f.length::integer, f.release_year::integer
    FROM requested q
    LEFT JOIN ranked r ON r.country_id = q.country_id AND r.popularity = 1
    LEFT JOIN public.film f ON f.film_id = r.film_id
    LEFT JOIN public.language l ON l.language_id = f.language_id
    ORDER BY q.country_name, f.title, f.film_id;
END;
$$;

COMMENT ON FUNCTION core.most_popular_films_by_countries(text[]) IS
'Returns the most rented films per country, including ties. Countries without rentals have NULL film details. Invalid country names raise an error.';

-- Task 4: ILIKE matches case-insensitively; % matches any text.
-- A copy is available if it has no open rental. Leading % can require a title scan.
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(p_pattern text)
RETURNS TABLE(row_num bigint, film_title text, language text,
              customer_name text, rental_date timestamp without time zone)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog
AS $$
BEGIN
    IF p_pattern IS NULL OR btrim(p_pattern) = '' THEN
        RAISE EXCEPTION 'Title pattern cannot be NULL or blank'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT row_number() OVER (ORDER BY f.title, i.inventory_id),
           f.title::text,
           btrim(l.name),
           NULL::text,
           NULL::timestamp without time zone
    FROM public.film f
    JOIN public.language l ON l.language_id = f.language_id
    JOIN public.inventory i ON i.film_id = f.film_id
    WHERE f.title ILIKE p_pattern
      AND NOT EXISTS (
          SELECT 1
          FROM public.rental r
          WHERE r.inventory_id = i.inventory_id
            AND r.return_date IS NULL
      )
    ORDER BY f.title, i.inventory_id;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 1::bigint, 'No films in stock found'::text,
               NULL::text, NULL::text, NULL::timestamp without time zone;
    END IF;
END;
$$;

COMMENT ON FUNCTION core.films_in_stock_by_title(text) IS
'Returns one row per available copy matching the title pattern. If none match, returns one message row. Blank or NULL input raises an error.';

-- TASK 5. A unique expression index enforces normalized title uniqueness even
-- for concurrent/direct INSERTs, unlike an IF EXISTS check by itself.
-- Existing conflicting data must be resolved explicitly; do not delete films.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.film GROUP BY lower(btrim(title)) HAVING count(*)>1) THEN
        RAISE EXCEPTION 'Existing duplicate film titles: resolve before installing new_movie'
            USING ERRCODE='23505';
    END IF;
END;
$$;
CREATE UNIQUE INDEX IF NOT EXISTS film_title_normalized_func_hw_uq
    ON public.film (lower(btrim(title)));

CREATE OR REPLACE FUNCTION core.new_movie(
    p_title text,
    p_release_year integer DEFAULT extract(year FROM CURRENT_DATE)::integer,
    p_language text DEFAULT 'Klingon')
RETURNS integer
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog
AS $$
DECLARE v_language_id integer; v_count bigint; v_film_id integer;
BEGIN
    IF p_title IS NULL OR btrim(p_title) = '' OR char_length(btrim(p_title)) > 255 THEN
        RAISE EXCEPTION 'Title must contain 1–255 characters' USING ERRCODE = '22023';
    END IF;
    IF p_release_year IS NULL OR p_release_year NOT BETWEEN 1901 AND 2155 THEN
        RAISE EXCEPTION 'Release year must be between 1901 and 2155'
            USING ERRCODE = '22023'; -- Matches public.year domain in DVD Rental.
    END IF;
    IF p_language IS NULL OR btrim(p_language) = '' THEN
        RAISE EXCEPTION 'Language cannot be NULL or blank' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM public.film f
               WHERE lower(btrim(f.title)) = lower(btrim(p_title))) THEN
        RAISE EXCEPTION 'Movie title already exists: %', p_title USING ERRCODE = '23505';
    END IF;
    SELECT count(*), min(l.language_id) INTO v_count, v_language_id
    FROM public.language l WHERE lower(btrim(l.name)) = lower(btrim(p_language));
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Language must exist exactly once: % (matches: %)', p_language, v_count
            USING ERRCODE = '22023';
    END IF;
    -- Omitting film_id invokes its existing nextval/identity DEFAULT; never MAX(id)+1.
    -- RETURNING obtains the generated ID safely. No sequence resetting is performed.
    -- Stock is not created: adding a catalogue film does not purchase physical copies.
    INSERT INTO public.film(title, release_year, language_id,
                            rental_rate, rental_duration, replacement_cost)
    VALUES (btrim(p_title), p_release_year, v_language_id, 4.99, 3, 19.99)
    RETURNING film_id INTO v_film_id;
    RETURN v_film_id;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Film insert violates a unique key (duplicate title or unsynchronized ID sequence): %', p_title
        USING ERRCODE='23505', DETAIL=SQLERRM;
    -- Other failures retain their original SQLSTATE/details; they are not swallowed.
    -- An exception rolls back this statement and trigger effects. The surrounding
    -- transaction controls COMMIT/ROLLBACK. Sequence gaps after rollback are normal.
END;
$$;
COMMENT ON FUNCTION core.new_movie(text,integer,text) IS
'Insert one unique normalized movie title using the film ID default. Optional year=current year, language=Klingon. Existing language required; duplicates raise 23505; invalid input raises 22023. Atomic insert; returns generated film_id.';
COMMIT;

/* TESTS: safe to rerun. Expected exceptions are caught by SQLSTATE; an unexpected
   success/failure stops the test. Each object has valid and boundary/missing tests.
   Fixtures are rolled back. Sequence values may advance, which is intentional.
   No assertion depends on fixed IDs or a permanently changed clock/data set.
*/
BEGIN;
SET LOCAL client_min_messages = notice;

-- A partitioned teaching database may contain only old monthly partitions.
-- Create a catch-all ONLY inside this rollback-only transaction: it accepts
-- current-quarter and next-quarter boundary fixtures without persistent DDL.
-- Existing DEFAULT partitions are reused. Plain payment tables need no change.
-- A DEFAULT child is a regular partition removed automatically by ROLLBACK,
-- not a PostgreSQL TEMP table (a temporary child of a permanent parent is invalid).
DO $$
BEGIN
    IF (SELECT relkind='p' FROM pg_class WHERE oid='public.payment'::regclass)
       AND NOT EXISTS (
           SELECT 1 FROM pg_inherits x JOIN pg_class c ON c.oid=x.inhrelid
           WHERE x.inhparent='public.payment'::regclass
             AND pg_get_expr(c.relpartbound,c.oid)='DEFAULT') THEN
        CREATE TABLE core._func_hw_payment_fixture
            PARTITION OF public.payment DEFAULT;
    END IF;
END;
$$;

-- TASK 1 valid: independent calculation equals the view (true).
WITH expected AS (
    SELECT c.name::text AS category, sum(p.amount)::numeric AS total_sales_revenue
    FROM public.payment p
    JOIN public.rental r USING(rental_id)
    JOIN public.inventory i USING(inventory_id)
    JOIN public.film_category fc USING(film_id)
    JOIN public.category c USING(category_id)
    WHERE p.payment_date >= date_trunc('quarter', CURRENT_DATE::timestamp)
      AND p.payment_date < date_trunc('quarter', CURRENT_DATE::timestamp)+interval '3 months'
    GROUP BY c.category_id,c.name HAVING sum(p.amount)>0
)
SELECT NOT EXISTS (
 (TABLE expected EXCEPT TABLE core.sales_revenue_by_category_qtr)
 UNION ALL
 (TABLE core.sales_revenue_by_category_qtr EXCEPT TABLE expected)
) AS task1_matches_independent_query;

-- TASK 1 boundary fixture. Preserve all original rows; add just 3 temporary payments.
-- Current start +1.23 must increase related category totals; next-start +98.76
-- must NOT contribute. A synthetic zero-sales category must NOT appear.
DO $$
DECLARE v_q timestamp := date_trunc('quarter',CURRENT_DATE::timestamp);
        v_p public.payment%ROWTYPE; v_cat integer; v_before numeric; v_after numeric;
        v_zero integer; v_title text := '__FUNC_HW_ZERO_'||txid_current();
BEGIN
    SELECT p.* INTO v_p FROM public.payment p
    WHERE EXISTS (SELECT 1 FROM public.rental r JOIN public.inventory i USING(inventory_id)
                  JOIN public.film_category fc USING(film_id) WHERE r.rental_id=p.rental_id)
    ORDER BY p.payment_id LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Test requires one payment linked to a film category'; END IF;
    SELECT fc.category_id INTO v_cat FROM public.rental r
    JOIN public.inventory i USING(inventory_id) JOIN public.film_category fc USING(film_id)
    WHERE r.rental_id=v_p.rental_id ORDER BY fc.category_id LIMIT 1;
    SELECT coalesce((SELECT v.total_sales_revenue FROM core.sales_revenue_by_category_qtr v
                     JOIN public.category c ON c.name=v.category WHERE c.category_id=v_cat),0)
    INTO v_before;
    INSERT INTO public.payment(customer_id,staff_id,rental_id,amount,payment_date)
    VALUES(v_p.customer_id,v_p.staff_id,v_p.rental_id,1.23,v_q),
          (v_p.customer_id,v_p.staff_id,v_p.rental_id,98.76,v_q+interval '3 months');
    SELECT v.total_sales_revenue INTO v_after FROM core.sales_revenue_by_category_qtr v
    JOIN public.category c ON c.name=v.category WHERE c.category_id=v_cat;
    IF v_after IS DISTINCT FROM v_before+1.23 THEN RAISE EXCEPTION 'Quarter boundary test failed'; END IF;
    -- Existing film may be in multiple categories; a temporary extra category is safe.
    INSERT INTO public.category(name) VALUES (left(v_title,25)) RETURNING category_id INTO v_zero;
    INSERT INTO public.film_category(film_id,category_id)
    SELECT i.film_id,v_zero FROM public.rental r JOIN public.inventory i USING(inventory_id)
    WHERE r.rental_id=v_p.rental_id;
    -- Isolate the zero fixture from the preceding current positive fixture.
    UPDATE public.payment SET payment_date=v_q-interval '1 second'
    WHERE rental_id IN (
        SELECT r2.rental_id FROM public.rental r2
        JOIN public.inventory i2 USING(inventory_id)
        JOIN public.film_category fc2 USING(film_id) WHERE fc2.category_id=v_zero)
      AND payment_date>=v_q AND payment_date<v_q+interval '3 months';
    INSERT INTO public.payment(customer_id,staff_id,rental_id,amount,payment_date)
    VALUES(v_p.customer_id,v_p.staff_id,v_p.rental_id,0,v_q);
    IF EXISTS(SELECT 1 FROM core.sales_revenue_by_category_qtr WHERE category=left(v_title,25)) THEN
        RAISE EXCEPTION 'Zero-sales category was incorrectly included';
    END IF;
    RAISE NOTICE 'PASS Task 1: start included, next quarter excluded, zero sales excluded';
END;
$$;
ROLLBACK;

BEGIN;
SET LOCAL client_min_messages = notice;
-- TASK 2 valid historical period selected from actual data (normally 2007-Q1).
SELECT * FROM core.get_sales_revenue_by_category_qtr(
 (SELECT to_char(min(payment_date),'YYYY-"Q"Q') FROM public.payment));
-- Expected: positive category totals; no data => 0 rows, tested with a valid remote year.
SELECT count(*)=0 AS task2_no_data FROM core.get_sales_revenue_by_category_qtr('9999-Q4');
DO $$ BEGIN
    BEGIN
        PERFORM * FROM core.get_sales_revenue_by_category_qtr('2007-Q5');
        RAISE EXCEPTION 'Invalid quarter unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 2: Q5 rejected (22023)'; END;
    BEGIN
        PERFORM * FROM core.get_sales_revenue_by_category_qtr(NULL);
        RAISE EXCEPTION 'NULL quarter unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 2: NULL rejected'; END;
END $$;

-- TASK 3 valid: films tied for highest rental count, not merely one arbitrary tie.
SELECT * FROM core.most_popular_films_by_countries(ARRAY['Afghanistan','Brazil','United States']);
-- Expected: no repeated rows when same country occurs twice.
SELECT NOT EXISTS (
 (SELECT * FROM core.most_popular_films_by_countries(ARRAY['Brazil','Brazil'])
  EXCEPT ALL SELECT * FROM core.most_popular_films_by_countries(ARRAY['Brazil']))
) AS task3_deduplicates_input;
DO $$ DECLARE v_country text := '__FUNC_HW_NO_RENTALS_'||txid_current(); BEGIN
    BEGIN
        PERFORM * FROM core.most_popular_films_by_countries(ARRAY['__country_does_not_exist__']);
        RAISE EXCEPTION 'Unknown country unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 3: unknown country rejected'; END;
    INSERT INTO public.country(country) VALUES(v_country);
        IF NOT EXISTS (
        SELECT 1
        FROM core.most_popular_films_by_countries(ARRAY[v_country]) AS result
        WHERE result.country = v_country
          AND result.film IS NULL
    ) THEN
        RAISE EXCEPTION 'Expected a country row with NULL film details';
    END IF;
END $$;

-- TASK 4 valid: sequential row numbers, correct five output columns; available copies.
SELECT * FROM core.films_in_stock_by_title('%love%');
-- Expected: one result row with 'No films in stock found' in film_title. 
SELECT * FROM core.films_in_stock_by_title('__FUNC_HW_NO_SUCH_TITLE__');
DO $$ BEGIN
    BEGIN
        PERFORM * FROM core.films_in_stock_by_title(NULL);
        RAISE EXCEPTION 'NULL pattern unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 4: NULL pattern rejected'; END;
END $$;

-- TASK 5 valid + optional arguments + duplicate + missing language.
-- Klingon is absent from standard DVD Rental. Real calls then raise 22023;
-- this rollback-only fixture supplies the prerequisite to test defaults safely.
DO $$
DECLARE v_id integer; v_title text := '__FUNC_HW_NEW_'||txid_current(); v_lang text;
BEGIN
    IF NOT EXISTS(SELECT 1 FROM public.language WHERE lower(btrim(name))='klingon') THEN
        INSERT INTO public.language(name) VALUES('Klingon');
    END IF;
    v_id := core.new_movie(v_title);
    IF NOT EXISTS(SELECT 1 FROM public.film f JOIN public.language l USING(language_id)
                  WHERE f.film_id=v_id AND f.title=v_title
                    AND f.rental_rate=4.99 AND f.rental_duration=3 AND f.replacement_cost=19.99
                    AND f.release_year=extract(year FROM CURRENT_DATE)::integer AND btrim(l.name)='Klingon') THEN
        RAISE EXCEPTION 'new_movie defaults test failed';
    END IF;
    SELECT btrim(name) INTO v_lang FROM public.language ORDER BY language_id LIMIT 1;
    PERFORM core.new_movie(v_title||'_EXPLICIT',2006,v_lang);
    BEGIN
        PERFORM core.new_movie(lower(v_title));
        RAISE EXCEPTION 'Duplicate title unexpectedly accepted';
    EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS Task 5: duplicate rejected (23505)'; END;
    BEGIN
        PERFORM core.new_movie(v_title||'_BADLANG',2006,'__missing_language__');
        RAISE EXCEPTION 'Missing language unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 5: missing language rejected'; END;
    BEGIN
        PERFORM core.new_movie(' ',2006,v_lang);
        RAISE EXCEPTION 'Blank title unexpectedly accepted';
    EXCEPTION WHEN invalid_parameter_value THEN RAISE NOTICE 'PASS Task 5: blank title rejected'; END;
    RAISE NOTICE 'PASS Task 5: generated ID %, default and explicit parameters verified',v_id;
END;
$$;
ROLLBACK;
-- End: core objects + title uniqueness index persist; all test data is rolled back.
