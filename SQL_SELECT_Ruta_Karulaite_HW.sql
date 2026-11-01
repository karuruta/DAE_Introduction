/*
SQL SELECT homework -- Ruta Karulaite
Database: dvdrental, PostgreSQL, schema public.
Each task has JOIN, subquery and CTE solutions (24 queries in total).

Database structure:
- rental and payment store transactions.
- film, actor, category, staff, store and address store entity details.
- film_actor and film_category connect actors and categories to films.
- inventory stores film copies and identifies their stores.
- Store revenue follows payment -> rental -> inventory -> store.

General assumptions:
- Revenue means the sum of payment.amount, not profit.
- Date filters use the database session's time zone.
- Top-N results contain exactly N rows; IDs resolve equal totals.
- These are my proposed business assumptions, not confirmed mentor decisions.
- The solution names describe the main approach; CTEs and subqueries can use JOINs.

Testing:
All queries were run in pgAdmin. The three versions of each task returned
matching results. The complete file also ran without errors.
Performance was not measured. Comments describe possible costs, not proven speed.
*/

/*
PART 1.1 -- Animation films

Assumptions:
2017-2019 includes both end years. Rate means rental_rate.
Use the Animation category; no extra age-rating filter was requested.
Return each film once, sorted by title and then film_id.

Comparison:
JOIN follows the table relationships, but DISTINCT may add sorting work.
EXISTS checks category membership without duplicating films; its link to the
outer query takes some care to read.
CTE gives the Animation film list a name, but adds code for this simple task.
Production choice: EXISTS, because only category membership is needed.
*/

/*
Task 1.1 -- JOIN solution.
List Animation films released in 2017-2019 with rental_rate > 1,
sorted alphabetically; return each film once.
JOIN behavior: INNER JOIN requires a matching Animation category.
*/
SELECT DISTINCT
    f.film_id,
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film AS f
INNER JOIN public.film_category AS fc
    ON fc.film_id = f.film_id
INNER JOIN public.category AS c
    ON c.category_id = fc.category_id
WHERE c.name = 'Animation'
  AND f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title, f.film_id;

/*
Task 1.1 -- Subquery solution.
List Animation films released in 2017-2019 with rental_rate > 1,
sorted alphabetically; return each film once.
JOIN behavior: INNER JOIN inside EXISTS connects film categories to their names.
*/
SELECT
    f.film_id,
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film AS f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND EXISTS (
      SELECT 1
      FROM public.film_category AS fc
      INNER JOIN public.category AS c
          ON c.category_id = fc.category_id
      WHERE fc.film_id = f.film_id
        AND c.name = 'Animation'
  )
ORDER BY f.title, f.film_id;

/*
Task 1.1 -- CTE solution.
List Animation films released in 2017-2019 with rental_rate > 1,
sorted alphabetically; return each film once.
JOIN behavior: INNER JOIN builds category membership and retains only qualifying films.
*/
WITH animation_films AS (
    SELECT DISTINCT fc.film_id
    FROM public.film_category AS fc
    INNER JOIN public.category AS c
        ON c.category_id = fc.category_id
    WHERE c.name = 'Animation'
)
SELECT
    f.film_id,
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film AS f
INNER JOIN animation_films AS af
    ON af.film_id = f.film_id
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title, f.film_id;

/*
PART 1.2 -- Store revenue since April 2017

Assumptions:
Include payments from 2017-04-01 onward; no end date was given.
Use the rental copy's store, not the employee's current store.
Include stores with no revenue as zero. Omit blank address2 values.
Assume every store has an address and inventory.store_id represents the rental
store. A payment without a rental/store link cannot be assigned to a store.

Comparison:
JOIN shows the full payment path, but groups many detail rows. Keep the date
filter in ON so stores without payments remain in the result.
The subquery is easy to read for a few stores, but may repeat the calculation
for each store.
CTE calculates revenue first, then adds addresses; it is slightly longer.
Production choice: CTE, because calculation and address formatting are separate.
*/

/*
Task 1.2 -- JOIN solution.
Calculate revenue for each store since 2017-04-01, including zero-revenue
stores. Output address and address2 combined as store_address, plus revenue.
JOIN behavior: INNER JOIN adds required addresses. LEFT JOIN preserves stores without
inventory, rentals or qualifying payments; the date filter stays in ON.
*/
SELECT
    CONCAT_WS(', ', a.address, NULLIF(TRIM(a.address2), '')) AS store_address,
    COALESCE(SUM(p.amount), 0) AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
    ON a.address_id = s.address_id
LEFT JOIN public.inventory AS i
    ON i.store_id = s.store_id
LEFT JOIN public.rental AS r
    ON r.inventory_id = i.inventory_id
LEFT JOIN public.payment AS p
    ON p.rental_id = r.rental_id
   AND p.payment_date >= DATE '2017-04-01'
GROUP BY s.store_id, a.address, a.address2
ORDER BY revenue DESC, s.store_id;

/*
Task 1.2 -- Subquery solution.
Calculate revenue for each store since 2017-04-01, including zero-revenue
stores. Output address and address2 combined as store_address, plus revenue.
JOIN behavior: INNER JOIN adds required addresses. INNER JOINs inside the scalar
subquery count only linked payments; COALESCE returns zero for no payments.
*/
SELECT
    CONCAT_WS(', ', a.address, NULLIF(TRIM(a.address2), '')) AS store_address,
    COALESCE((
        SELECT SUM(p.amount)
        FROM public.inventory AS i
        INNER JOIN public.rental AS r
            ON r.inventory_id = i.inventory_id
        INNER JOIN public.payment AS p
            ON p.rental_id = r.rental_id
        WHERE i.store_id = s.store_id
          AND p.payment_date >= DATE '2017-04-01'
    ), 0) AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
    ON a.address_id = s.address_id
ORDER BY revenue DESC, s.store_id;

/*
Task 1.2 -- CTE solution.
Calculate revenue for each store since 2017-04-01, including zero-revenue
stores. Output address and address2 combined as store_address, plus revenue.
JOIN behavior: INNER JOINs aggregate linked payments and add required addresses.
LEFT JOIN to totals preserves stores with no revenue; COALESCE supplies zero.
*/
WITH store_revenue AS (
    SELECT
        i.store_id,
        SUM(p.amount) AS revenue
    FROM public.inventory AS i
    INNER JOIN public.rental AS r
        ON r.inventory_id = i.inventory_id
    INNER JOIN public.payment AS p
        ON p.rental_id = r.rental_id
    WHERE p.payment_date >= DATE '2017-04-01'
    GROUP BY i.store_id
)
SELECT
    CONCAT_WS(', ', a.address, NULLIF(TRIM(a.address2), '')) AS store_address,
    COALESCE(sr.revenue, 0) AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
    ON a.address_id = s.address_id
LEFT JOIN store_revenue AS sr
    ON sr.store_id = s.store_id
ORDER BY revenue DESC, s.store_id;

/*
PART 1.3 -- Top five actors by film count

Assumptions:
Include films released in 2015 or later. Count distinct films, not copies.
Exclude actors with no matching films. Resolve equal counts by actor_id.

Comparison:
JOIN is short and follows actor -> film_actor -> film. DISTINCT counting can
require extra work, but makes it clear that each film counts once.
The subquery calculates a count for each actor, which may repeat table access.
CTE separates counts from names, but adds a step to a simple report.
Production choice: JOIN, because the filtering and counting are clear together.
*/

/*
Task 1.3 -- JOIN solution.
Show the top five actors by distinct film count for releases since 2015.
Output first_name, last_name, number_of_movies; sort count descending.
JOIN behavior: INNER JOIN excludes actors with no qualifying film.
*/
SELECT
    a.first_name,
    a.last_name,
    COUNT(DISTINCT f.film_id) AS number_of_movies
FROM public.actor AS a
INNER JOIN public.film_actor AS fa
    ON fa.actor_id = a.actor_id
INNER JOIN public.film AS f
    ON f.film_id = fa.film_id
WHERE f.release_year >= 2015
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY number_of_movies DESC, a.actor_id
LIMIT 5;

/*
Task 1.3 -- Subquery solution.
Show the top five actors by distinct film count for releases since 2015.
Output first_name, last_name, number_of_movies; sort count descending.
JOIN behavior: INNER JOIN inside the count includes qualifying film credits only.
The outer positive-count filter excludes actors without qualifying films.
*/
SELECT
    ac.first_name,
    ac.last_name,
    ac.number_of_movies
FROM (
    SELECT
        a.actor_id,
        a.first_name,
        a.last_name,
        (
            SELECT COUNT(DISTINCT f.film_id)
            FROM public.film_actor AS fa
            INNER JOIN public.film AS f
                ON f.film_id = fa.film_id
            WHERE fa.actor_id = a.actor_id
              AND f.release_year >= 2015
        ) AS number_of_movies
    FROM public.actor AS a
) AS ac
WHERE ac.number_of_movies > 0
ORDER BY ac.number_of_movies DESC, ac.actor_id
LIMIT 5;

/*
Task 1.3 -- CTE solution.
Show the top five actors by distinct film count for releases since 2015.
Output first_name, last_name, number_of_movies; sort count descending.
JOIN behavior: INNER JOINs connect qualifying film credits and add actor names.
Actors without qualifying films have no count row and are excluded.
*/
WITH actor_movie_counts AS (
    SELECT
        fa.actor_id,
        COUNT(DISTINCT f.film_id) AS number_of_movies
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
    WHERE f.release_year >= 2015
    GROUP BY fa.actor_id
)
SELECT
    a.first_name,
    a.last_name,
    amc.number_of_movies
FROM actor_movie_counts AS amc
INNER JOIN public.actor AS a
    ON a.actor_id = amc.actor_id
ORDER BY amc.number_of_movies DESC, a.actor_id
LIMIT 5;

/*
PART 1.4 -- Film counts by genre and year

Assumptions:
Include every known release year in film, even if all three counts are zero.
Exclude NULL years. Count a film once per genre; a film can belong to several.
Use zero when a genre has no films in a year.

Comparison:
JOIN calculates all three counts together. The CASE expressions are repetitive,
and DISTINCT counting may use extra memory or sorting.
The subquery separates the genres clearly, but repeats a count for each year
and genre.
CTE names the intermediate totals, but needs more code and grouping steps.
Production choice: JOIN with conditional counts for these three fixed genres.
*/

/*
Task 1.4 -- JOIN solution.
Count Drama, Travel and Documentary films per known release_year.
Include zero counts; sort release_year descending.
JOIN behavior: LEFT JOIN preserves films and years without matching categories.
Conditional COUNT returns zero when a genre has no matching film.
*/
SELECT
    f.release_year,
    COUNT(DISTINCT CASE WHEN c.name = 'Drama' THEN f.film_id END)
        AS number_of_drama_movies,
    COUNT(DISTINCT CASE WHEN c.name = 'Travel' THEN f.film_id END)
        AS number_of_travel_movies,
    COUNT(DISTINCT CASE WHEN c.name = 'Documentary' THEN f.film_id END)
        AS number_of_documentary_movies
FROM public.film AS f
LEFT JOIN public.film_category AS fc
    ON fc.film_id = f.film_id
LEFT JOIN public.category AS c
    ON c.category_id = fc.category_id
WHERE f.release_year IS NOT NULL
GROUP BY f.release_year
ORDER BY f.release_year DESC;

/*
Task 1.4 -- Subquery solution.
Count Drama, Travel and Documentary films per known release_year.
Include zero counts; sort release_year descending.
JOIN behavior: INNER JOINs inside counts require matching genre membership.
The outer year list preserves every known release year; COUNT returns zero.
*/
SELECT
    y.release_year,
    (
        SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc
            ON fc.film_id = f.film_id
        INNER JOIN public.category AS c
            ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND c.name = 'Drama'
    ) AS number_of_drama_movies,
    (
        SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc
            ON fc.film_id = f.film_id
        INNER JOIN public.category AS c
            ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND c.name = 'Travel'
    ) AS number_of_travel_movies,
    (
        SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc
            ON fc.film_id = f.film_id
        INNER JOIN public.category AS c
            ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND c.name = 'Documentary'
    ) AS number_of_documentary_movies
FROM (
    SELECT DISTINCT f.release_year
    FROM public.film AS f
    WHERE f.release_year IS NOT NULL
) AS y
ORDER BY y.release_year DESC;

/*
Task 1.4 -- CTE solution.
Count Drama, Travel and Documentary films per known release_year.
Include zero counts; sort release_year descending.
JOIN behavior: INNER JOINs build matching genre totals; LEFT JOIN preserves
all known years. COALESCE changes absent totals to zero.
*/
WITH release_years AS (
    SELECT DISTINCT f.release_year
    FROM public.film AS f
    WHERE f.release_year IS NOT NULL
),
genre_counts AS (
    SELECT
        f.release_year,
        c.name AS genre,
        COUNT(DISTINCT f.film_id) AS number_of_movies
    FROM public.film AS f
    INNER JOIN public.film_category AS fc
        ON fc.film_id = f.film_id
    INNER JOIN public.category AS c
        ON c.category_id = fc.category_id
    WHERE f.release_year IS NOT NULL
      AND c.name IN ('Drama', 'Travel', 'Documentary')
    GROUP BY f.release_year, c.name
)
SELECT
    y.release_year,
    COALESCE(MAX(CASE WHEN gc.genre = 'Drama'
        THEN gc.number_of_movies END), 0) AS number_of_drama_movies,
    COALESCE(MAX(CASE WHEN gc.genre = 'Travel'
        THEN gc.number_of_movies END), 0) AS number_of_travel_movies,
    COALESCE(MAX(CASE WHEN gc.genre = 'Documentary'
        THEN gc.number_of_movies END), 0) AS number_of_documentary_movies
FROM release_years AS y
LEFT JOIN genre_counts AS gc
    ON gc.release_year = y.release_year
GROUP BY y.release_year
ORDER BY y.release_year DESC;

/*
PART 2.1 -- Top three employees and their last store in 2017

Assumptions:
Use payment_date from 2017-01-01 up to, but not including, 2018-01-01.
Count all of the employee's payments in that year, regardless of store.
The last store comes from the latest payment's rental/inventory link.
Do not use staff.store_id, which shows the current store.
If dates are equal, use the greater payment_id as a tie-breaker.
Keep payments with missing rental links; their store may be unknown (NULL).
Assume inventory's recorded store represents the store for that rental.

Comparison:
CTE makes the steps clear, but finding a later payment with NOT EXISTS can
involve many comparisons.
The subquery finds the last payment using ORDER BY and LIMIT 1. Repeating this
lookup can cost more without suitable indexes.
JOIN finds the latest date, then the greatest payment_id at that date. This
avoids joining all payment pairs, but the nested query is harder to read.
Production choice: subquery for its clear last-payment lookup; check its plan
and indexes before using it with a much larger payment table.
*/

/*
Task 2.1 -- CTE solution.
Show the three employees with the most revenue in 2017 and their last
store within 2017. Use payment_date only; employees may work in several stores.
A processed payment identifies the workplace through rental/inventory.
Resolve date ties by payment_id descending and revenue ties by staff_id.
JOIN behavior: LEFT JOIN preserves payments with missing rental/inventory links.
INNER JOIN connects each revenue total to staff and the selected last payment.
*/
WITH payments_2017 AS (
    SELECT
        p.payment_id,
        p.staff_id,
        p.payment_date,
        p.amount,
        i.store_id
    FROM public.payment AS p
    LEFT JOIN public.rental AS r
        ON r.rental_id = p.rental_id
    LEFT JOIN public.inventory AS i
        ON i.inventory_id = r.inventory_id
    WHERE p.payment_date >= DATE '2017-01-01'
      AND p.payment_date < DATE '2018-01-01'
),
staff_revenue AS (
    SELECT
        p.staff_id,
        SUM(p.amount) AS revenue
    FROM payments_2017 AS p
    GROUP BY p.staff_id
),
last_staff_payment AS (
    SELECT
        p.staff_id,
        p.store_id,
        p.payment_date
    FROM payments_2017 AS p
    WHERE NOT EXISTS (
        SELECT 1
        FROM payments_2017 AS newer
        WHERE newer.staff_id = p.staff_id
          AND (
              newer.payment_date > p.payment_date
              OR (
                  newer.payment_date = p.payment_date
                  AND newer.payment_id > p.payment_id
              )
          )
    )
)
SELECT
    s.staff_id,
    s.first_name,
    s.last_name,
    lp.store_id AS last_store_id,
    sr.revenue
FROM staff_revenue AS sr
INNER JOIN public.staff AS s
    ON s.staff_id = sr.staff_id
INNER JOIN last_staff_payment AS lp
    ON lp.staff_id = sr.staff_id
ORDER BY sr.revenue DESC, s.staff_id
LIMIT 3;

/*
Task 2.1 -- Subquery solution.
Show the three employees with the most revenue in 2017 and their last
store within 2017. Use payment_date only; employees may work in several stores.
A processed payment identifies the workplace through rental/inventory.
Resolve date ties by payment_id descending and revenue ties by staff_id.
JOIN behavior: INNER JOIN adds staff details. LEFT JOIN preserves the latest
payment even if its rental/inventory is missing; the store is then NULL.
*/
SELECT
    s.staff_id,
    s.first_name,
    s.last_name,
    (
        SELECT i.store_id
        FROM public.payment AS p
        LEFT JOIN public.rental AS r
            ON r.rental_id = p.rental_id
        LEFT JOIN public.inventory AS i
            ON i.inventory_id = r.inventory_id
        WHERE p.staff_id = s.staff_id
          AND p.payment_date >= DATE '2017-01-01'
          AND p.payment_date < DATE '2018-01-01'
        ORDER BY p.payment_date DESC, p.payment_id DESC
        LIMIT 1
    ) AS last_store_id,
    sr.revenue
FROM (
    SELECT
        p.staff_id,
        SUM(p.amount) AS revenue
    FROM public.payment AS p
    WHERE p.payment_date >= DATE '2017-01-01'
      AND p.payment_date < DATE '2018-01-01'
    GROUP BY p.staff_id
) AS sr
INNER JOIN public.staff AS s
    ON s.staff_id = sr.staff_id
ORDER BY sr.revenue DESC, s.staff_id
LIMIT 3;

/*
Task 2.1 -- JOIN solution.
Show the three employees with the most revenue in 2017 and their last
store within 2017. Use payment_date only; employees may work in several stores.
A processed payment identifies the workplace through rental/inventory.
Resolve date ties by payment_id descending and revenue ties by staff_id.
JOIN behavior: INNER JOIN connects totals, staff and one latest payment per employee.
LEFT JOIN preserves the selected payment when rental/inventory links are missing.
*/
SELECT
    s.staff_id,
    s.first_name,
    s.last_name,
    i.store_id AS last_store_id,
    sr.revenue
FROM (
    SELECT
        p.staff_id,
        SUM(p.amount) AS revenue
    FROM public.payment AS p
    WHERE p.payment_date >= DATE '2017-01-01'
      AND p.payment_date < DATE '2018-01-01'
    GROUP BY p.staff_id
) AS sr
INNER JOIN public.staff AS s
    ON s.staff_id = sr.staff_id
INNER JOIN (
    SELECT
        p.staff_id,
        MAX(p.payment_id) AS last_payment_id
    FROM public.payment AS p
    INNER JOIN (
        SELECT
            latest.staff_id,
            MAX(latest.payment_date) AS last_payment_date
        FROM public.payment AS latest
        WHERE latest.payment_date >= DATE '2017-01-01'
          AND latest.payment_date < DATE '2018-01-01'
        GROUP BY latest.staff_id
    ) AS ld
        ON ld.staff_id = p.staff_id
       AND ld.last_payment_date = p.payment_date
    GROUP BY p.staff_id
) AS lp
    ON lp.staff_id = sr.staff_id
INNER JOIN public.payment AS last_p
    ON last_p.payment_id = lp.last_payment_id
LEFT JOIN public.rental AS r
    ON r.rental_id = last_p.rental_id
LEFT JOIN public.inventory AS i
    ON i.inventory_id = r.inventory_id
ORDER BY sr.revenue DESC, s.staff_id
LIMIT 3;

/*
PART 2.2 -- Top five films by rental count

Assumptions:
Count rentals across all dates and stores, including unreturned films.
Do not join payment, because several payments could duplicate a rental.
Ratings describe suitable audiences, not the actual ages of viewers.
G: all ages; PG: parental guidance; PG-13: caution for children under 13;
R: under 17 needs an accompanying parent/adult guardian; NC-17: ages 18+.
Resolve equal rental counts by film_id and return exactly five films.
References:
https://en.wikipedia.org/wiki/Motion_Picture_Association_film_rating_system
https://www.filmratings.com/ratings-guide/

Comparison:
JOIN is direct, but includes film details in the grouped rental calculation.
The subquery counts each film separately, which may repeat table access.
CTE groups rentals by film first, then adds the title and audience description.
It adds a query block but keeps counting separate from presentation.
Production choice: CTE for the clear separation of these two steps.
*/

/*
Task 2.2 -- JOIN solution.
Show the five most rented films, rental counts and expected audience
age guidance based on MPA ratings. Count all dates/stores and unreturned rentals;
return exactly five rows, resolving count ties by film_id.
JOIN behavior: INNER JOIN includes films with inventory and rentals only.
Each rental is counted once without payment rows.
*/
SELECT
    f.film_id,
    f.title,
    COUNT(r.rental_id) AS number_of_rentals,
    f.rating,
    CASE f.rating::text
        WHEN 'G' THEN
            'All ages'
        WHEN 'PG' THEN
            'Parental guidance suggested; no fixed minimum age'
        WHEN 'PG-13' THEN
            'Some material may be inappropriate for children under 13'
        WHEN 'R' THEN
            'Under 17 requires an accompanying parent or adult guardian'
        WHEN 'NC-17' THEN
            '18 and older only'
        ELSE
            'Unknown rating'
    END AS expected_audience
FROM public.film AS f
INNER JOIN public.inventory AS i
    ON i.film_id = f.film_id
INNER JOIN public.rental AS r
    ON r.inventory_id = i.inventory_id
GROUP BY f.film_id, f.title, f.rating
ORDER BY number_of_rentals DESC, f.film_id
LIMIT 5;

/*
Task 2.2 -- Subquery solution.
Show the five most rented films, rental counts and expected audience
age guidance based on MPA ratings. Count all dates/stores and unreturned rentals;
return exactly five rows, resolving count ties by film_id.
JOIN behavior: INNER JOIN in the correlated count connects copies to rentals.
The outer positive-count filter excludes films without rentals.
*/
SELECT
    movie_counts.film_id,
    movie_counts.title,
    movie_counts.number_of_rentals,
    movie_counts.rating,
    CASE movie_counts.rating::text
        WHEN 'G' THEN
            'All ages'
        WHEN 'PG' THEN
            'Parental guidance suggested; no fixed minimum age'
        WHEN 'PG-13' THEN
            'Some material may be inappropriate for children under 13'
        WHEN 'R' THEN
            'Under 17 requires an accompanying parent or adult guardian'
        WHEN 'NC-17' THEN
            '18 and older only'
        ELSE
            'Unknown rating'
    END AS expected_audience
FROM (
    SELECT
        f.film_id,
        f.title,
        f.rating,
        (
            SELECT COUNT(r.rental_id)
            FROM public.inventory AS i
            INNER JOIN public.rental AS r
                ON r.inventory_id = i.inventory_id
            WHERE i.film_id = f.film_id
        ) AS number_of_rentals
    FROM public.film AS f
) AS movie_counts
WHERE movie_counts.number_of_rentals > 0
ORDER BY movie_counts.number_of_rentals DESC, movie_counts.film_id
LIMIT 5;

/*
Task 2.2 -- CTE solution.
Show the five most rented films, rental counts and expected audience
age guidance based on MPA ratings. Count all dates/stores and unreturned rentals;
return exactly five rows, resolving count ties by film_id.
JOIN behavior: INNER JOIN connects rentals to inventory and adds film details.
Films without rentals have no CTE count row and are excluded.
*/
WITH movie_rentals AS (
    SELECT
        i.film_id,
        COUNT(r.rental_id) AS number_of_rentals
    FROM public.inventory AS i
    INNER JOIN public.rental AS r
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)
SELECT
    f.film_id,
    f.title,
    mr.number_of_rentals,
    f.rating,
    CASE f.rating::text
        WHEN 'G' THEN
            'All ages'
        WHEN 'PG' THEN
            'Parental guidance suggested; no fixed minimum age'
        WHEN 'PG-13' THEN
            'Some material may be inappropriate for children under 13'
        WHEN 'R' THEN
            'Under 17 requires an accompanying parent or adult guardian'
        WHEN 'NC-17' THEN
            '18 and older only'
        ELSE
            'Unknown rating'
    END AS expected_audience
FROM movie_rentals AS mr
INNER JOIN public.film AS f
    ON f.film_id = mr.film_id
ORDER BY mr.number_of_rentals DESC, f.film_id
LIMIT 5;

/*
PART 3, V1 -- Years since the latest release

Assumptions:
Use only films recorded in this database, not an actor's whole real career.
Subtract the latest release year from the current year.
Exclude future and NULL years. Keep actors without eligible films as NULL.
Show all actors, with the longest gaps first; resolve ties by actor_id.

Comparison:
CTE separates the latest year from actor details, but adds a query block.
The subquery is easy to understand per actor, but may repeat film lookups.
JOIN calculates MAX in one grouped query. Keep the year condition in ON so
actors without eligible films are preserved.
Production choice: JOIN, because this is a simple grouped calculation.
*/

/*
Task 3 V1 -- CTE solution.
Calculate the gap between each actor's latest release year and the current
year. Exclude future/unknown years; preserve actors without eligible films as NULL.
Show all actors, longest gaps first; resolve ties by actor_id.
JOIN behavior: INNER JOIN builds eligible film credits. LEFT JOIN preserves
actors with no eligible release and produces NULL for their gap.
*/
WITH latest_actor_release AS (
    SELECT
        fa.actor_id,
        MAX(f.release_year) AS latest_release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
    WHERE f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
    GROUP BY fa.actor_id
)
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    lar.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE)::integer
        - lar.latest_release_year AS years_since_latest_release
FROM public.actor AS a
LEFT JOIN latest_actor_release AS lar
    ON lar.actor_id = a.actor_id
ORDER BY years_since_latest_release DESC NULLS LAST, a.actor_id;

/*
Task 3 V1 -- Subquery solution.
Calculate the gap between each actor's latest release year and the current
year. Exclude future/unknown years; preserve actors without eligible films as NULL.
Show all actors, longest gaps first; resolve ties by actor_id.
JOIN behavior: INNER JOIN inside MAX connects eligible film credits.
The outer actor query preserves every actor; no eligible year gives NULL.
*/
SELECT
    actor_releases.actor_id,
    actor_releases.first_name,
    actor_releases.last_name,
    actor_releases.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE)::integer
        - actor_releases.latest_release_year AS years_since_latest_release
FROM (
    SELECT
        a.actor_id,
        a.first_name,
        a.last_name,
        (
            SELECT MAX(f.release_year)
            FROM public.film_actor AS fa
            INNER JOIN public.film AS f
                ON f.film_id = fa.film_id
            WHERE fa.actor_id = a.actor_id
              AND f.release_year
                  <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
        ) AS latest_release_year
    FROM public.actor AS a
) AS actor_releases
ORDER BY years_since_latest_release DESC NULLS LAST, actor_releases.actor_id;

/*
Task 3 V1 -- JOIN solution.
Calculate the gap between each actor's latest release year and the current
year. Exclude future/unknown years; preserve actors without eligible films as NULL.
Show all actors, longest gaps first; resolve ties by actor_id.
JOIN behavior: LEFT JOIN preserves every actor. The year condition stays in ON
so actors without eligible films are not removed. MAX ignores NULL years.
*/
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    MAX(f.release_year) AS latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE)::integer
        - MAX(f.release_year) AS years_since_latest_release
FROM public.actor AS a
LEFT JOIN public.film_actor AS fa
    ON fa.actor_id = a.actor_id
LEFT JOIN public.film AS f
    ON f.film_id = fa.film_id
   AND f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY years_since_latest_release DESC NULLS LAST, a.actor_id;

/*
PART 3, V2 -- Gaps between consecutive release years

Assumptions:
Use distinct active years per actor; several films in one year count as one
active year because their order within the year is unknown.
Exclude future and NULL years. Compare only consecutive active years.
Gap means next_year - previous_year: 1995 to 2004 is a gap of 9 years,
with 8 full calendar years without releases in between.
Show all gaps, longest first, including ties. Actors with fewer than two
eligible active years have no between-release gap and are excluded.

Comparison:
CTE defines the active years once and makes the steps easy to follow, but
joining earlier and later years can create many intermediate pairs.
The subquery finds the next year with MIN; repeated searches may cost more.
JOIN also finds the nearest later year, but repeats the active-year definition
and can create many intermediate pairs.
Production choice under the no-window-functions rule: CTE for readability.
For larger histories, compare execution plans before choosing an approach.
*/

/*
Task 3 V2 -- CTE solution.
Find gaps between consecutive distinct film release years for each actor;
show all gaps, longest first. Collapse same-year films, exclude future/unknown
years, and use next_year - previous_year. Actors need two eligible years.
Keep equal longest gaps; order ties by actor_id and previous_release_year.
JOIN behavior: INNER JOIN connects credits to films and pairs years for the same actor.
MIN selects the nearest later year. The final INNER JOIN adds actor details.
*/
WITH actor_release_years AS (
    SELECT DISTINCT
        fa.actor_id,
        f.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
    WHERE f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
),
consecutive_releases AS (
    SELECT
        earlier.actor_id,
        earlier.release_year AS previous_release_year,
        MIN(later.release_year) AS next_release_year
    FROM actor_release_years AS earlier
    INNER JOIN actor_release_years AS later
        ON later.actor_id = earlier.actor_id
       AND later.release_year > earlier.release_year
    GROUP BY earlier.actor_id, earlier.release_year
)
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    cr.previous_release_year,
    cr.next_release_year,
    cr.next_release_year - cr.previous_release_year AS gap_years
FROM consecutive_releases AS cr
INNER JOIN public.actor AS a
    ON a.actor_id = cr.actor_id
ORDER BY gap_years DESC, a.actor_id, cr.previous_release_year;

/*
Task 3 V2 -- Subquery solution.
Find gaps between consecutive distinct film release years for each actor;
show all gaps, longest first. Collapse same-year films, exclude future/unknown
years, and use next_year - previous_year. Actors need two eligible years.
Keep equal longest gaps; order ties by actor_id and previous_release_year.
JOIN behavior: INNER JOIN connects film credits to films and adds actor details.
The correlated MIN finds the next release; the outer filter removes final years.
*/
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    gaps.previous_release_year,
    gaps.next_release_year,
    gaps.next_release_year - gaps.previous_release_year AS gap_years
FROM (
    SELECT
        active_years.actor_id,
        active_years.release_year AS previous_release_year,
        (
            SELECT MIN(f2.release_year)
            FROM public.film_actor AS fa2
            INNER JOIN public.film AS f2
                ON f2.film_id = fa2.film_id
            WHERE fa2.actor_id = active_years.actor_id
              AND f2.release_year > active_years.release_year
              AND f2.release_year
                  <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
        ) AS next_release_year
    FROM (
        SELECT DISTINCT
            fa.actor_id,
            f.release_year
        FROM public.film_actor AS fa
        INNER JOIN public.film AS f
            ON f.film_id = fa.film_id
        WHERE f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
    ) AS active_years
) AS gaps
INNER JOIN public.actor AS a
    ON a.actor_id = gaps.actor_id
WHERE gaps.next_release_year IS NOT NULL
ORDER BY gap_years DESC, a.actor_id, gaps.previous_release_year;

/*
Task 3 V2 -- JOIN solution.
Find gaps between consecutive distinct film release years for each actor;
show all gaps, longest first. Collapse same-year films, exclude future/unknown
years, and use next_year - previous_year. Actors need two eligible years.
Keep equal longest gaps; order ties by actor_id and previous_release_year.
JOIN behavior: INNER JOIN pairs active years with later years for the same actor.
MIN selects the nearest later year; years without a later release are excluded.
*/
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    earlier.release_year AS previous_release_year,
    MIN(later.release_year) AS next_release_year,
    MIN(later.release_year) - earlier.release_year AS gap_years
FROM public.actor AS a
INNER JOIN (
    SELECT DISTINCT
        fa.actor_id,
        f.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
    WHERE f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
) AS earlier
    ON earlier.actor_id = a.actor_id
INNER JOIN (
    SELECT DISTINCT
        fa.actor_id,
        f.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
    WHERE f.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
) AS later
    ON later.actor_id = earlier.actor_id
   AND later.release_year > earlier.release_year
GROUP BY a.actor_id, a.first_name, a.last_name, earlier.release_year
ORDER BY gap_years DESC, a.actor_id, earlier.release_year;
