-- PostgreSQL / dvdrental. Run one transaction at a time in pgAdmin.
-- Inspect RETURNING and SELECT before executing each COMMIT separately.
-- If a step fails or its result is unexpected, run ROLLBACK in the same tab.
-- INSERT ... SELECT resolves IDs from the current database and filters out
-- existing rows in the same statement. Literal VALUES alone cannot do those
-- lookups; here VALUES supplies only fixed input such as titles and prices.
-- Earlier committed steps are unaffected. Sequential reruns skip ex rows.

-- 1. Add the three films independently of their category and cast links.
-- Commit the film rows first because later category and cast links need them.
BEGIN;
INSERT INTO public.film (title, release_year, language_id, rental_rate,
                         rental_duration, last_update)
SELECT src.title, src.release_year, lang.language_id, src.rate,
       src.days, CURRENT_DATE
FROM (VALUES ('Influencers', 2025, 4.99, 7),
             ('Ladies First', 2026, 9.99, 14),
             ('Fair Play', 2023, 19.99, 21))
    AS src(title, release_year, rate, days)
CROSS JOIN (
    SELECT language_id FROM public.language
    WHERE LOWER(TRIM(name)) = 'english'
    ORDER BY language_id LIMIT 1
) AS lang
-- INSERT SELECT resolves the language FK and skips a matching title/year.
WHERE NOT EXISTS (
    SELECT 1 FROM public.film AS fm
    WHERE UPPER(fm.title) = UPPER(src.title)
      AND fm.release_year = src.release_year
)
RETURNING film_id, title, release_year, rental_rate, rental_duration;
COMMIT;

-- 2. Assign ex categories. Rollback affects only the new links.
-- Keep category links separate so a bad category mapping leaves the films intact.
BEGIN;
INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT fm.film_id, cat.category_id, CURRENT_DATE
FROM (VALUES ('INFLUENCERS', 2025, 'Horror'),
             ('LADIES FIRST', 2026, 'Comedy'),
             ('FAIR PLAY', 2023, 'Drama'))
    AS src(title, release_year, category_name)
INNER JOIN public.film AS fm
    ON UPPER(fm.title) = src.title AND fm.release_year = src.release_year
INNER JOIN public.category AS cat ON cat.name = src.category_name
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_category AS fc
    WHERE fc.film_id = fm.film_id AND fc.category_id = cat.category_id
)
RETURNING film_id, category_id;
COMMIT;

-- 3. Add actors and cast links together so a failure leaves neither half saved.
-- Match full names ignoring case and outer spaces; this assumes no homonyms.
-- The new actor and the link that uses its ID belong in the same transaction.
BEGIN;
CREATE TEMP TABLE homework_cast ON COMMIT DROP AS
SELECT * FROM (VALUES
    ('INFLUENCERS', 2025, 'Cassandra', 'Naud'),
    ('INFLUENCERS', 2025, 'Georgina', 'Campbell'),
    ('LADIES FIRST', 2026, 'Sacha', 'Baron Cohen'),
    ('LADIES FIRST', 2026, 'Rosamund', 'Pike'),
    ('FAIR PLAY', 2023, 'Phoebe', 'Dynevor'),
    ('FAIR PLAY', 2023, 'Alden', 'Ehrenreich')
) AS src(title, release_year, first_name, last_name);

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT DISTINCT src.first_name, src.last_name, CURRENT_DATE
FROM pg_temp.homework_cast AS src
WHERE NOT EXISTS (
    SELECT 1 FROM public.actor AS act
    WHERE UPPER(TRIM(act.first_name)) = UPPER(src.first_name)
      AND UPPER(TRIM(act.last_name)) = UPPER(src.last_name)
)
RETURNING actor_id, first_name, last_name;

-- Resolve both foreign keys. A scalar lookup rejects ambiguous actor names.
WITH ci AS (
    SELECT fm.film_id,
           (SELECT act.actor_id FROM public.actor AS act
            WHERE UPPER(TRIM(act.first_name)) = UPPER(src.first_name)
              AND UPPER(TRIM(act.last_name)) = UPPER(src.last_name)) AS actor_id
    FROM pg_temp.homework_cast AS src
    INNER JOIN public.film AS fm
        ON UPPER(fm.title) = src.title AND fm.release_year = src.release_year
)
INSERT INTO public.film_actor (film_id, actor_id, last_update)
SELECT ci.film_id, ci.actor_id, CURRENT_DATE
FROM ci
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor AS fa
    WHERE fa.film_id = ci.film_id AND fa.actor_id = ci.actor_id
)
RETURNING film_id, actor_id;
COMMIT;

-- 4. Add one copy per film to the store with the lowest store_id.
-- Rollback affects only the added copies. Existing film/store pairs are skipped.
-- Verify the store and its film copies independently before recording rentals.
BEGIN;
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT fm.film_id, st.store_id, CURRENT_DATE
FROM public.film AS fm
CROSS JOIN (SELECT MIN(store_id) AS store_id FROM public.store) AS st
WHERE (UPPER(fm.title), fm.release_year) IN
    (('INFLUENCERS', 2025), ('LADIES FIRST', 2026), ('FAIR PLAY', 2023))
AND NOT EXISTS (
    SELECT 1 FROM public.inventory AS inv
    WHERE inv.film_id = fm.film_id AND inv.store_id = st.store_id
)
RETURNING inventory_id, film_id, store_id;
COMMIT;

-- 5. Change one eligible customer. The test email prevents selecting
-- a second customer on a rerun. Reuse an address without editing its row.
-- Verify the selected customer and the qualifying counts before deleting history.
BEGIN;
WITH chosen_customer AS (
    SELECT cust.customer_id
    FROM public.customer AS cust
    WHERE (SELECT COUNT(*) FROM public.rental AS rent
           WHERE rent.customer_id = cust.customer_id) >= 43
      AND (SELECT COUNT(*) FROM public.payment AS pay
           WHERE pay.customer_id = cust.customer_id) >= 43
      AND NOT EXISTS (
          SELECT 1 FROM public.customer AS ex
          WHERE LOWER(ex.email) = 'ruta.karulaite@example.com'
      )
    ORDER BY cust.customer_id LIMIT 1
),
chosen_address AS (
    SELECT st.address_id FROM public.store AS st ORDER BY st.store_id LIMIT 1
)
UPDATE public.customer AS cust
SET first_name = 'Ruta', last_name = 'Karulaite',
    email = 'ruta.karulaite@example.com',
    address_id = chosen_address.address_id, last_update = CURRENT_DATE
FROM chosen_customer
CROSS JOIN chosen_address
WHERE cust.customer_id = chosen_customer.customer_id
RETURNING cust.customer_id, cust.first_name, cust.last_name, cust.email,
          cust.address_id, cust.last_update;

-- First run: verify one customer with at least 43 of each. Rollback if wrong.
SELECT cust.customer_id, cust.first_name, cust.last_name, addr.address,
       (SELECT COUNT(*) FROM public.rental AS rent
        WHERE rent.customer_id = cust.customer_id) AS rental_count,
       (SELECT COUNT(*) FROM public.payment AS pay
        WHERE pay.customer_id = cust.customer_id) AS payment_count
FROM public.customer AS cust
INNER JOIN public.address AS addr ON addr.address_id = cust.address_id
WHERE LOWER(cust.email) = 'ruta.karulaite@example.com';
COMMIT;

-- 6. Remove historical transactions for the selected customer only.
-- Delete payments first because they reference rentals. Rollback restores
-- both sets of rows if either delete fails. Fixed cutoffs spare the 2026 batch.
-- Keep cleanup separate from the new rentals so the historical counts can be verified.
-- The email selects only the exercise customer, and the date cutoffs protect
-- the new batch. Customer, inventory and other customers’ records are untouched.
BEGIN;
DELETE FROM public.payment AS pay
WHERE pay.customer_id = (
    SELECT cust.customer_id FROM public.customer AS cust
    WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
)
AND pay.payment_date < TIMESTAMPTZ '2018-01-01 00:00:00+00'
RETURNING pay.payment_id, pay.rental_id, pay.payment_date;

DELETE FROM public.rental AS rent
WHERE rent.customer_id = (
    SELECT cust.customer_id FROM public.customer AS cust
    WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
)
AND rent.rental_date < TIMESTAMPTZ '2006-01-01 00:00:00+00'
RETURNING rent.rental_id, rent.rental_date;

-- Verify the customer still exists and both historical counts are zero.
SELECT cust.customer_id, cust.first_name, cust.last_name,
       (SELECT COUNT(*) FROM public.rental AS rent
        WHERE rent.customer_id = cust.customer_id
          AND rent.rental_date < TIMESTAMPTZ '2006-01-01 00:00:00+00') AS old_rentals,
       (SELECT COUNT(*) FROM public.payment AS pay
        WHERE pay.customer_id = cust.customer_id
          AND pay.payment_date < TIMESTAMPTZ '2018-01-01 00:00:00+00') AS old_payments
FROM public.customer AS cust
WHERE LOWER(cust.email) = 'ruta.karulaite@example.com';
COMMIT;

-- 7. Add the November 2026 partition and record rentals and payments together.
-- If a payment fails, rollback also removes the new rentals and partition.
-- Commit the partition, rentals and payments together so no unpaid batch remains.
BEGIN;
CREATE TABLE IF NOT EXISTS public.payment_p2026_11
    PARTITION OF public.payment
    FOR VALUES FROM ('2026-11-01 00:00:00+00')
               TO   ('2026-12-01 00:00:00+00');

-- Use one inventory copy per film; resolve the customer and store manager
-- from ex rows. The fixed timestamp identifies the homework batch.
WITH chosen_inventory AS (
    SELECT DISTINCT ON (fm.film_id) inv.inventory_id, st.manager_staff_id,
           fm.rental_duration
    FROM public.inventory AS inv
    INNER JOIN public.film AS fm ON fm.film_id = inv.film_id
    INNER JOIN public.store AS st ON st.store_id = inv.store_id
    WHERE st.store_id = (SELECT MIN(store_id) FROM public.store)
      AND (UPPER(fm.title), fm.release_year) IN
          (('INFLUENCERS', 2025), ('LADIES FIRST', 2026), ('FAIR PLAY', 2023))
    ORDER BY fm.film_id, inv.inventory_id
)
INSERT INTO public.rental (rental_date, inventory_id, customer_id, staff_id, return_date, last_update)
SELECT TIMESTAMPTZ '2026-11-07 09:00:00+00', src.inventory_id,
       cust.customer_id, src.manager_staff_id,
       TIMESTAMPTZ '2026-11-07 09:00:00+00' + src.rental_duration * INTERVAL '1 day',
       CURRENT_DATE
FROM chosen_inventory AS src
CROSS JOIN public.customer AS cust
WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
  AND NOT EXISTS (
      SELECT 1 FROM public.rental AS rent
      WHERE rent.customer_id = cust.customer_id
        AND rent.inventory_id = src.inventory_id
        AND rent.rental_date = TIMESTAMPTZ '2026-11-07 09:00:00+00'
  )
RETURNING rental_id, inventory_id, customer_id, staff_id;

-- Backfill returns if the earlier version of this homework already ran.
-- Only the three films, exercise customer, store and batch timestamp qualify.
UPDATE public.rental AS rent
SET return_date = rent.rental_date + fm.rental_duration * INTERVAL '1 day',
    last_update = CURRENT_DATE
FROM public.inventory AS inv
INNER JOIN public.film AS fm ON fm.film_id = inv.film_id
WHERE rent.inventory_id = inv.inventory_id
  AND rent.customer_id = (
      SELECT cust.customer_id FROM public.customer AS cust
      WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
  )
  AND inv.store_id = (SELECT MIN(store_id) FROM public.store)
  AND rent.rental_date = TIMESTAMPTZ '2026-11-07 09:00:00+00'
  AND (UPPER(fm.title), fm.release_year) IN
      (('INFLUENCERS', 2025), ('LADIES FIRST', 2026), ('FAIR PLAY', 2023))
  AND rent.return_date IS NULL
RETURNING rent.rental_id, rent.return_date;

-- Reuse rental_id and charge the stored rental rate once per rental.
-- The payment schema does not have a last_update column.
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT rent.customer_id, rent.staff_id, rent.rental_id, fm.rental_rate, rent.rental_date
FROM public.rental AS rent
INNER JOIN public.customer AS cust ON cust.customer_id = rent.customer_id
INNER JOIN public.inventory AS inv ON inv.inventory_id = rent.inventory_id
INNER JOIN public.film AS fm ON fm.film_id = inv.film_id
WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
  AND rent.rental_date = TIMESTAMPTZ '2026-11-07 09:00:00+00'
  AND inv.store_id = (SELECT MIN(store_id) FROM public.store)
  AND (UPPER(fm.title), fm.release_year) IN
      (('INFLUENCERS', 2025), ('LADIES FIRST', 2026), ('FAIR PLAY', 2023))
  AND NOT EXISTS (
      SELECT 1 FROM public.payment AS pay WHERE pay.rental_id = rent.rental_id
  )
RETURNING payment_id, rental_id, amount, payment_date;

-- Verify three rows, each with a payment, before committing.
SELECT fm.title, inv.store_id, rent.rental_id, rent.return_date,
       pay.payment_id, pay.amount,
       pay.tableoid::regclass AS payment_partition
FROM public.customer AS cust
INNER JOIN public.rental AS rent ON rent.customer_id = cust.customer_id
INNER JOIN public.inventory AS inv ON inv.inventory_id = rent.inventory_id
INNER JOIN public.film AS fm ON fm.film_id = inv.film_id
LEFT JOIN public.payment AS pay ON pay.rental_id = rent.rental_id
WHERE LOWER(cust.email) = 'ruta.karulaite@example.com'
  AND rent.rental_date = TIMESTAMPTZ '2026-11-07 09:00:00+00'
ORDER BY fm.title;
COMMIT;
