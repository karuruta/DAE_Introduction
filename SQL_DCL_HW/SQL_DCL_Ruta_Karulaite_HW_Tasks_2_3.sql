-- Run once as the administrator in an isolated dvdrental copy.
-- Assumes the standard public.customer, public.rental and public.payment tables.
-- Run the entire script. See Messages for PASS notices and actual SQLSTATE 42501 errors.
-- Grants and policies are committed; test row changes are rolled back.
BEGIN;

CREATE ROLE rentaluser LOGIN INHERIT PASSWORD 'rentalpassword';
CREATE ROLE rental NOLOGIN;

-- PUBLIC grants are inherited by all roles. Change these only in the lab copy.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rentaluser', current_database());
END $$;

-- Explicit SET ROLE is needed to test as the user. CONNECT itself is checked
-- at login; has_database_privilege checks the catalog grant here.
SET LOCAL ROLE rentaluser;
SELECT current_user, has_database_privilege(current_database(), 'CONNECT') AS can_connect;
DO $$
BEGIN
    IF NOT has_database_privilege(current_database(), 'CONNECT')
       OR has_database_privilege(current_database(), 'TEMP') THEN
        RAISE EXCEPTION 'Unexpected database privileges';
    END IF;
    BEGIN
        PERFORM 1 FROM public.customer;
        RAISE EXCEPTION 'Unexpected customer access';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS initial SELECT denied [%]: %', SQLSTATE, SQLERRM;
    END;
END $$;
RESET ROLE;

GRANT USAGE ON SCHEMA public TO rentaluser;
GRANT SELECT ON public.customer TO rentaluser;
SET LOCAL ROLE rentaluser;
SELECT * FROM public.customer;
DO $$
BEGIN
    BEGIN
        UPDATE public.customer SET active = 0 WHERE false;
        RAISE EXCEPTION 'Unexpected customer UPDATE';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS customer UPDATE denied [%]: %', SQLSTATE, SQLERRM;
    END;
END $$;
RESET ROLE;

GRANT rental TO rentaluser;
GRANT USAGE ON SCHEMA public TO rental;
GRANT INSERT, UPDATE ON public.rental TO rental;
-- UPDATE ... WHERE rental_id = ... also needs SELECT on rental_id.
GRANT SELECT (rental_id) ON public.rental TO rental;
-- A restored database can use nextval() without an OWNED BY link.
-- In that case, find the sequence referenced by the column's default.
DO $$
DECLARE
    seq regclass := pg_get_serial_sequence('public.rental', 'rental_id')::regclass;
BEGIN
    IF seq IS NULL THEN
        SELECT s.oid::regclass INTO STRICT seq
        FROM pg_attribute a
        JOIN pg_attrdef ad ON ad.adrelid = a.attrelid
                          AND ad.adnum = a.attnum
        JOIN pg_depend d ON d.classid = 'pg_attrdef'::regclass
                        AND d.objid = ad.oid
                        AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class s ON s.oid = d.refobjid AND s.relkind = 'S'
        WHERE a.attrelid = 'public.rental'::regclass
          AND a.attname = 'rental_id'
          AND NOT a.attisdropped;
    END IF;

    EXECUTE format('GRANT USAGE ON SEQUENCE %s TO rental', seq);
END $$;

SAVEPOINT rental_write_tests;
DO $$
DECLARE
    sample public.rental%ROWTYPE;
    changed integer;
BEGIN
    SELECT * INTO STRICT sample FROM public.rental ORDER BY rental_id LIMIT 1;
    SET LOCAL ROLE rentaluser;
    IF NOT pg_has_role(current_user, 'rental', 'USAGE') THEN
        RAISE EXCEPTION 'Group privileges are not inherited';
    END IF;
    INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id)
    VALUES (clock_timestamp(), sample.inventory_id, sample.customer_id, NULL, sample.staff_id);
    UPDATE public.rental SET return_date = sample.rental_date + interval '1 day'
    WHERE rental_id = sample.rental_id;
    GET DIAGNOSTICS changed = ROW_COUNT;
    IF changed <> 1 THEN RAISE EXCEPTION 'Expected exactly one updated row'; END IF;
    RAISE NOTICE 'PASS group INSERT and UPDATE';
    BEGIN
        DELETE FROM public.rental WHERE false;
        RAISE EXCEPTION 'Unexpected DELETE';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS DELETE denied [%]: %', SQLSTATE, SQLERRM;
    END;
    RESET ROLE;
END $$;
ROLLBACK TO SAVEPOINT rental_write_tests;

REVOKE INSERT ON public.rental FROM rental;
SET LOCAL ROLE rentaluser;
DO $$
BEGIN
    BEGIN
        INSERT INTO public.rental (rental_date, inventory_id, customer_id, staff_id)
        SELECT now(), 1, 1, 1 WHERE false;
        RAISE EXCEPTION 'Unexpected INSERT after REVOKE';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS INSERT after REVOKE denied [%]: %', SQLSTATE, SQLERRM;
    END;
    IF NOT has_table_privilege('public.rental', 'UPDATE') THEN
        RAISE EXCEPTION 'UPDATE was unexpectedly lost';
    END IF;
END $$;
RESET ROLE;

-- Task 3: start with the lab's baseline: no pre-existing policies on these tables.
-- Stop rather than silently combining this exercise with other policies.
DO $$
DECLARE
    chosen record;
    client text;
    tbl text;
    own_count bigint;
    other_count bigint;
BEGIN
    IF EXISTS (SELECT FROM pg_policies WHERE schemaname = 'public'
               AND tablename IN ('rental', 'payment')) THEN
        RAISE EXCEPTION 'Existing policies found. Review Task 1 before proceeding.';
    END IF;

    SELECT c.customer_id, c.first_name, c.last_name INTO STRICT chosen
    FROM public.customer AS c
    WHERE EXISTS (SELECT FROM public.rental AS r WHERE r.customer_id = c.customer_id)
      AND EXISTS (SELECT FROM public.payment AS p WHERE p.customer_id = c.customer_id)
    ORDER BY c.customer_id LIMIT 1;

    client := 'client_' || regexp_replace(lower(chosen.first_name || '_' || chosen.last_name),
                                          '[^a-z0-9_]', '_', 'g');
    EXECUTE format('CREATE ROLE %I NOLOGIN', client);
    EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', client);

    FOREACH tbl IN ARRAY ARRAY['rental', 'payment'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
        EXECUTE format('GRANT SELECT ON public.%I TO %I', tbl, client);
        EXECUTE format('CREATE POLICY client_own_rows ON public.%I FOR SELECT TO %I USING (customer_id = %L)',
                       tbl, client, chosen.customer_id);
    END LOOP;

    -- Preserve staff UPDATE and the rental_id read required by its WHERE clause.
    CREATE POLICY staff_read_rental ON public.rental FOR SELECT TO rental USING (true);
    CREATE POLICY staff_update_rental ON public.rental FOR UPDATE TO rental
        USING (true) WITH CHECK (true);

    -- First confirm other clients' rows really exist as administrator.
    IF NOT EXISTS (SELECT FROM public.rental WHERE customer_id <> chosen.customer_id)
       OR NOT EXISTS (SELECT FROM public.payment WHERE customer_id <> chosen.customer_id) THEN
        RAISE EXCEPTION 'Need rows for a different customer to demonstrate RLS';
    END IF;
    EXECUTE format('SET LOCAL ROLE %I', client);
    FOREACH tbl IN ARRAY ARRAY['rental', 'payment'] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I WHERE customer_id = $1', tbl)
            INTO own_count USING chosen.customer_id;
        EXECUTE format('SELECT count(*) FROM public.%I WHERE customer_id <> $1', tbl)
            INTO other_count USING chosen.customer_id;
        IF own_count = 0 OR other_count <> 0 THEN
            RAISE EXCEPTION 'RLS failed for %: own %, other %', tbl, own_count, other_count;
        END IF;
        RAISE NOTICE 'PASS %, customer_id %, table %: own rows %, other rows %',
            current_user, chosen.customer_id, tbl, own_count, other_count;
    END LOOP;
    RESET ROLE;
    RAISE NOTICE 'Manual check: SET ROLE %; use customer_id %; finish with RESET ROLE.',
        quote_ident(client), chosen.customer_id;
END $$;

COMMIT;

-- Optional screenshots: substitute the role and ID printed in Messages.
-- SET ROLE client_first_last;
-- SELECT * FROM public.rental  WHERE customer_id = 1;  -- replace 1
-- SELECT * FROM public.payment WHERE customer_id = 1;
-- SELECT * FROM public.rental  WHERE customer_id <> 1; -- zero rows
-- SELECT * FROM public.payment WHERE customer_id <> 1; -- zero rows
-- RESET ROLE;
-- For actual LOGIN evidence, open a new pgAdmin connection as rentaluser,
-- then run SELECT session_user, current_user; and SELECT * FROM public.customer;
