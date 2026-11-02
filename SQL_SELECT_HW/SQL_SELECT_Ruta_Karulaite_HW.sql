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
- Base-table aliases are consistent: film, actor, cat, fc (film_category),
  fa (film_actor), inv (inventory), rent (rental), pay (payment), staff,
  store and addr (address). Self-joins use role names where needed.
- These are my proposed business assumptions, not confirmed mentor decisions.
- The solution names describe the main approach; CTEs and subqueries can use JOINs.

Testing:
The previous version ran in pgAdmin without errors, with matching results
for each task. This revision changes aliases and Task 2.1 store logic;
re-run all queries in pgAdmin before committing.
Performance was not measured. Comments describe possible costs, not proven speed.
*/

/*
PART 1.1 -- Animation films

Assumptions:
2017-2019 includes both end years. Rate means rental_rate.
Use the Animation category; no extra age-rating filter was requested.
Assume Animation identifies one category and film-category pairs are unique.
Return each film once, sorted by title and then film_id.

Comparison:
JOIN follows the table relationships. No DISTINCT is needed: each film has
one link to the Animation category, so that join does not multiply films.
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
SELECT
    film.film_id,
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
INNER JOIN public.film_category AS fc
    ON fc.film_id = film.film_id
INNER JOIN public.category AS cat
    ON cat.category_id = fc.category_id
WHERE cat.name = 'Animation'
  AND film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
ORDER BY film.title, film.film_id;

/*
Task 1.1 -- Subquery solution.
List Animation films released in 2017-2019 with rental_rate > 1,
sorted alphabetically; return each film once.
JOIN behavior: INNER JOIN inside EXISTS connects film categories to their names.
*/
SELECT
    film.film_id,
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
WHERE film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
  AND EXISTS (
      SELECT 1
      FROM public.film_category AS fc
      INNER JOIN public.category AS cat
          ON cat.category_id = fc.category_id
      WHERE fc.film_id = film.film_id
        AND cat.name = 'Animation'
  )
ORDER BY film.title, film.film_id;

/*
Task 1.1 -- CTE solution.
List Animation films released in 2017-2019 with rental_rate > 1,
sorted alphabetically; return each film once.
JOIN behavior: INNER JOIN builds category membership and retains only qualifying films.
*/
WITH animation_films AS (
    SELECT fc.film_id
    FROM public.film_category AS fc
    INNER JOIN public.category AS cat
        ON cat.category_id = fc.category_id
    WHERE cat.name = 'Animation'
)
SELECT
    film.film_id,
    film.title,
    film.release_year,
    film.rental_rate
FROM public.film AS film
INNER JOIN animation_films AS animation
    ON animation.film_id = film.film_id
WHERE film.release_year BETWEEN 2017 AND 2019
  AND film.rental_rate > 1
ORDER BY film.title, film.film_id;

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
    CONCAT_WS(', ', addr.address, NULLIF(TRIM(addr.address2), '')) AS store_address,
    COALESCE(SUM(pay.amount), 0) AS revenue
FROM public.store AS store
INNER JOIN public.address AS addr
    ON addr.address_id = store.address_id
LEFT JOIN public.inventory AS inv
    ON inv.store_id = store.store_id
LEFT JOIN public.rental AS rent
    ON rent.inventory_id = inv.inventory_id
LEFT JOIN public.payment AS pay
    ON pay.rental_id = rent.rental_id
   AND pay.payment_date >= DATE '2017-04-01'
GROUP BY store.store_id, addr.address, addr.address2
ORDER BY revenue DESC, store.store_id;

/*
Task 1.2 -- Subquery solution.
Calculate revenue for each store since 2017-04-01, including zero-revenue
stores. Output address and address2 combined as store_address, plus revenue.
JOIN behavior: INNER JOIN adds required addresses. INNER JOINs inside the scalar
subquery count only linked payments; COALESCE returns zero for no payments.
*/
SELECT
    CONCAT_WS(', ', addr.address, NULLIF(TRIM(addr.address2), '')) AS store_address,
    COALESCE((
        SELECT SUM(pay.amount)
        FROM public.inventory AS inv
        INNER JOIN public.rental AS rent
            ON rent.inventory_id = inv.inventory_id
        INNER JOIN public.payment AS pay
            ON pay.rental_id = rent.rental_id
        WHERE inv.store_id = store.store_id
          AND pay.payment_date >= DATE '2017-04-01'
    ), 0) AS revenue
FROM public.store AS store
INNER JOIN public.address AS addr
    ON addr.address_id = store.address_id
ORDER BY revenue DESC, store.store_id;

/*
Task 1.2 -- CTE solution.
Calculate revenue for each store since 2017-04-01, including zero-revenue
stores. Output address and address2 combined as store_address, plus revenue.
JOIN behavior: INNER JOINs aggregate linked payments and add required addresses.
LEFT JOIN to totals preserves stores with no revenue; COALESCE supplies zero.
*/
WITH store_revenue AS (
    SELECT
        inv.store_id,
        SUM(pay.amount) AS revenue
    FROM public.inventory AS inv
    INNER JOIN public.rental AS rent
        ON rent.inventory_id = inv.inventory_id
    INNER JOIN public.payment AS pay
        ON pay.rental_id = rent.rental_id
    WHERE pay.payment_date >= DATE '2017-04-01'
    GROUP BY inv.store_id
)
SELECT
    CONCAT_WS(', ', addr.address, NULLIF(TRIM(addr.address2), '')) AS store_address,
    COALESCE(store_totals.revenue, 0) AS revenue
FROM public.store AS store
INNER JOIN public.address AS addr
    ON addr.address_id = store.address_id
LEFT JOIN store_revenue AS store_totals
    ON store_totals.store_id = store.store_id
ORDER BY revenue DESC, store.store_id;

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
    actor.first_name,
    actor.last_name,
    COUNT(DISTINCT film.film_id) AS number_of_movies
FROM public.actor AS actor
INNER JOIN public.film_actor AS fa
    ON fa.actor_id = actor.actor_id
INNER JOIN public.film AS film
    ON film.film_id = fa.film_id
WHERE film.release_year >= 2015
GROUP BY actor.actor_id, actor.first_name, actor.last_name
ORDER BY number_of_movies DESC, actor.actor_id
LIMIT 5;

/*
Task 1.3 -- Subquery solution.
Show the top five actors by distinct film count for releases since 2015.
Output first_name, last_name, number_of_movies; sort count descending.
JOIN behavior: INNER JOIN inside the count includes qualifying film credits only.
The outer positive-count filter excludes actors without qualifying films.
*/
SELECT
    actor_counts.first_name,
    actor_counts.last_name,
    actor_counts.number_of_movies
FROM (
    SELECT
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        (
            SELECT COUNT(DISTINCT film.film_id)
            FROM public.film_actor AS fa
            INNER JOIN public.film AS film
                ON film.film_id = fa.film_id
            WHERE fa.actor_id = actor.actor_id
              AND film.release_year >= 2015
        ) AS number_of_movies
    FROM public.actor AS actor
) AS actor_counts
WHERE actor_counts.number_of_movies > 0
ORDER BY actor_counts.number_of_movies DESC, actor_counts.actor_id
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
        COUNT(DISTINCT film.film_id) AS number_of_movies
    FROM public.film_actor AS fa
    INNER JOIN public.film AS film
        ON film.film_id = fa.film_id
    WHERE film.release_year >= 2015
    GROUP BY fa.actor_id
)
SELECT
    actor.first_name,
    actor.last_name,
    actor_counts.number_of_movies
FROM actor_movie_counts AS actor_counts
INNER JOIN public.actor AS actor
    ON actor.actor_id = actor_counts.actor_id
ORDER BY actor_counts.number_of_movies DESC, actor.actor_id
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
    film.release_year,
    COUNT(DISTINCT CASE WHEN cat.name = 'Drama' THEN film.film_id END)
        AS number_of_drama_movies,
    COUNT(DISTINCT CASE WHEN cat.name = 'Travel' THEN film.film_id END)
        AS number_of_travel_movies,
    COUNT(DISTINCT CASE WHEN cat.name = 'Documentary' THEN film.film_id END)
        AS number_of_documentary_movies
FROM public.film AS film
LEFT JOIN public.film_category AS fc
    ON fc.film_id = film.film_id
LEFT JOIN public.category AS cat
    ON cat.category_id = fc.category_id
WHERE film.release_year IS NOT NULL
GROUP BY film.release_year
ORDER BY film.release_year DESC;

/*
Task 1.4 -- Subquery solution.
Count Drama, Travel and Documentary films per known release_year.
Include zero counts; sort release_year descending.
JOIN behavior: INNER JOINs inside counts require matching genre membership.
The outer year list preserves every known release year; COUNT returns zero.
*/
SELECT
    years.release_year,
    (
        SELECT COUNT(DISTINCT film.film_id)
        FROM public.film AS film
        INNER JOIN public.film_category AS fc
            ON fc.film_id = film.film_id
        INNER JOIN public.category AS cat
            ON cat.category_id = fc.category_id
        WHERE film.release_year = years.release_year
          AND cat.name = 'Drama'
    ) AS number_of_drama_movies,
    (
        SELECT COUNT(DISTINCT film.film_id)
        FROM public.film AS film
        INNER JOIN public.film_category AS fc
            ON fc.film_id = film.film_id
        INNER JOIN public.category AS cat
            ON cat.category_id = fc.category_id
        WHERE film.release_year = years.release_year
          AND cat.name = 'Travel'
    ) AS number_of_travel_movies,
    (
        SELECT COUNT(DISTINCT film.film_id)
        FROM public.film AS film
        INNER JOIN public.film_category AS fc
            ON fc.film_id = film.film_id
        INNER JOIN public.category AS cat
            ON cat.category_id = fc.category_id
        WHERE film.release_year = years.release_year
          AND cat.name = 'Documentary'
    ) AS number_of_documentary_movies
FROM (
    SELECT DISTINCT film.release_year
    FROM public.film AS film
    WHERE film.release_year IS NOT NULL
) AS years
ORDER BY years.release_year DESC;

/*
Task 1.4 -- CTE solution.
Count Drama, Travel and Documentary films per known release_year.
Include zero counts; sort release_year descending.
JOIN behavior: INNER JOINs build matching genre totals; LEFT JOIN preserves
all known years. COALESCE changes absent totals to zero.
*/
WITH release_years AS (
    SELECT DISTINCT film.release_year
    FROM public.film AS film
    WHERE film.release_year IS NOT NULL
),
genre_counts AS (
    SELECT
        film.release_year,
        cat.name AS genre,
        COUNT(DISTINCT film.film_id) AS number_of_movies
    FROM public.film AS film
    INNER JOIN public.film_category AS fc
        ON fc.film_id = film.film_id
    INNER JOIN public.category AS cat
        ON cat.category_id = fc.category_id
    WHERE film.release_year IS NOT NULL
      AND cat.name IN ('Drama', 'Travel', 'Documentary')
    GROUP BY film.release_year, cat.name
)
SELECT
    years.release_year,
    COALESCE(MAX(CASE WHEN gc.genre = 'Drama'
        THEN gc.number_of_movies END), 0) AS number_of_drama_movies,
    COALESCE(MAX(CASE WHEN gc.genre = 'Travel'
        THEN gc.number_of_movies END), 0) AS number_of_travel_movies,
    COALESCE(MAX(CASE WHEN gc.genre = 'Documentary'
        THEN gc.number_of_movies END), 0) AS number_of_documentary_movies
FROM release_years AS years
LEFT JOIN genre_counts AS gc
    ON gc.release_year = years.release_year
GROUP BY years.release_year
ORDER BY years.release_year DESC;

/*
PART 2.1 -- Top three employees and their stores in 2017

Assumptions:
Use payment_date from 2017-01-01 up to, but not including, 2018-01-01.
Count all payments processed by each employee during that year.
Following the review clarification, take the employee's store from staff.store_id,
not from rental/inventory. Keep the output name last_store_id for this report.
This is the latest store recorded for the employee; the schema has no dated
staff-store history to reconstruct a different last store specifically in 2017.
A payment without a rental still counts toward employee revenue.
Return exactly three employees, resolving equal revenue by staff_id.

Comparison:
CTE calculates revenue per employee, then adds staff details. It makes the two
steps clear, but adds a query block for a simple report.
The subquery calculates revenue for each employee; repeated lookups may cost
more without suitable indexes. EXISTS excludes employees without 2017 payments.
JOIN groups payments and staff together. It is short and needs no last-payment
search, because the requested store is already available in staff.
Production choice: JOIN for its simple grouping and direct store source.
*/

/*
Task 2.1 -- CTE solution.
Show the three employees with the most revenue in 2017 and their stores.
Use payment_date only and staff.store_id, as clarified by the reviewer.
Include payments without rentals; resolve equal revenue by staff_id.
JOIN behavior: INNER JOIN adds staff names/store to each employee's revenue.
Employees without 2017 payments have no revenue row and are excluded.
*/
WITH staff_revenue AS (
    SELECT
        pay.staff_id,
        SUM(pay.amount) AS revenue
    FROM public.payment AS pay
    WHERE pay.payment_date >= DATE '2017-01-01'
      AND pay.payment_date < DATE '2018-01-01'
    GROUP BY pay.staff_id
)
SELECT
    staff.staff_id,
    staff.first_name,
    staff.last_name,
    staff.store_id AS last_store_id,
    staff_totals.revenue
FROM staff_revenue AS staff_totals
INNER JOIN public.staff AS staff
    ON staff.staff_id = staff_totals.staff_id
ORDER BY staff_totals.revenue DESC, staff.staff_id
LIMIT 3;

/*
Task 2.1 -- Subquery solution.
Show the three employees with the most revenue in 2017 and their stores.
Use payment_date only and staff.store_id, as clarified by the reviewer.
Include payments without rentals; resolve equal revenue by staff_id.
JOIN behavior: no JOIN is needed. Correlated subqueries sum payments and
check that the employee processed at least one payment in 2017.
*/
SELECT
    staff.staff_id,
    staff.first_name,
    staff.last_name,
    staff.store_id AS last_store_id,
    (
        SELECT SUM(pay.amount)
        FROM public.payment AS pay
        WHERE pay.staff_id = staff.staff_id
          AND pay.payment_date >= DATE '2017-01-01'
          AND pay.payment_date < DATE '2018-01-01'
    ) AS revenue
FROM public.staff AS staff
WHERE EXISTS (
    SELECT 1
    FROM public.payment AS pay
    WHERE pay.staff_id = staff.staff_id
      AND pay.payment_date >= DATE '2017-01-01'
      AND pay.payment_date < DATE '2018-01-01'
)
ORDER BY revenue DESC, staff.staff_id
LIMIT 3;

/*
Task 2.1 -- JOIN solution.
Show the three employees with the most revenue in 2017 and their stores.
Use payment_date only and staff.store_id, as clarified by the reviewer.
Include payments without rentals; resolve equal revenue by staff_id.
Steps: join each payment to its employee, filter 2017 payments, sum per
employee, then sort and return the top three with the store from staff.
JOIN behavior: INNER JOIN includes employees with payments only.
No rental/inventory join is needed, so payments without rentals remain included.
*/
SELECT
    staff.staff_id,
    staff.first_name,
    staff.last_name,
    staff.store_id AS last_store_id,
    SUM(pay.amount) AS revenue
FROM public.staff AS staff
INNER JOIN public.payment AS pay
    ON pay.staff_id = staff.staff_id
WHERE pay.payment_date >= DATE '2017-01-01'
  AND pay.payment_date < DATE '2018-01-01'
GROUP BY
    staff.staff_id,
    staff.first_name,
    staff.last_name,
    staff.store_id
ORDER BY revenue DESC, staff.staff_id
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
    film.film_id,
    film.title,
    COUNT(rent.rental_id) AS number_of_rentals,
    film.rating,
    CASE film.rating::text
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
FROM public.film AS film
INNER JOIN public.inventory AS inv
    ON inv.film_id = film.film_id
INNER JOIN public.rental AS rent
    ON rent.inventory_id = inv.inventory_id
GROUP BY film.film_id, film.title, film.rating
ORDER BY number_of_rentals DESC, film.film_id
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
        film.film_id,
        film.title,
        film.rating,
        (
            SELECT COUNT(rent.rental_id)
            FROM public.inventory AS inv
            INNER JOIN public.rental AS rent
                ON rent.inventory_id = inv.inventory_id
            WHERE inv.film_id = film.film_id
        ) AS number_of_rentals
    FROM public.film AS film
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
        inv.film_id,
        COUNT(rent.rental_id) AS number_of_rentals
    FROM public.inventory AS inv
    INNER JOIN public.rental AS rent
        ON rent.inventory_id = inv.inventory_id
    GROUP BY inv.film_id
)
SELECT
    film.film_id,
    film.title,
    rental_counts.number_of_rentals,
    film.rating,
    CASE film.rating::text
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
FROM movie_rentals AS rental_counts
INNER JOIN public.film AS film
    ON film.film_id = rental_counts.film_id
ORDER BY rental_counts.number_of_rentals DESC, film.film_id
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
        MAX(film.release_year) AS latest_release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS film
        ON film.film_id = fa.film_id
    WHERE film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
    GROUP BY fa.actor_id
)
SELECT
    actor.actor_id,
    actor.first_name,
    actor.last_name,
    latest_release.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE)::integer
        - latest_release.latest_release_year AS years_since_latest_release
FROM public.actor AS actor
LEFT JOIN latest_actor_release AS latest_release
    ON latest_release.actor_id = actor.actor_id
ORDER BY years_since_latest_release DESC NULLS LAST, actor.actor_id;

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
        actor.actor_id,
        actor.first_name,
        actor.last_name,
        (
            SELECT MAX(film.release_year)
            FROM public.film_actor AS fa
            INNER JOIN public.film AS film
                ON film.film_id = fa.film_id
            WHERE fa.actor_id = actor.actor_id
              AND film.release_year
                  <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
        ) AS latest_release_year
    FROM public.actor AS actor
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
    actor.actor_id,
    actor.first_name,
    actor.last_name,
    MAX(film.release_year) AS latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE)::integer
        - MAX(film.release_year) AS years_since_latest_release
FROM public.actor AS actor
LEFT JOIN public.film_actor AS fa
    ON fa.actor_id = actor.actor_id
LEFT JOIN public.film AS film
    ON film.film_id = fa.film_id
   AND film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
GROUP BY actor.actor_id, actor.first_name, actor.last_name
ORDER BY years_since_latest_release DESC NULLS LAST, actor.actor_id;

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
        film.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS film
        ON film.film_id = fa.film_id
    WHERE film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
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
    actor.actor_id,
    actor.first_name,
    actor.last_name,
    release_gaps.previous_release_year,
    release_gaps.next_release_year,
    release_gaps.next_release_year - release_gaps.previous_release_year AS gap_years
FROM consecutive_releases AS release_gaps
INNER JOIN public.actor AS actor
    ON actor.actor_id = release_gaps.actor_id
ORDER BY gap_years DESC, actor.actor_id, release_gaps.previous_release_year;

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
    actor.actor_id,
    actor.first_name,
    actor.last_name,
    gaps.previous_release_year,
    gaps.next_release_year,
    gaps.next_release_year - gaps.previous_release_year AS gap_years
FROM (
    SELECT
        active_years.actor_id,
        active_years.release_year AS previous_release_year,
        (
            SELECT MIN(film.release_year)
            FROM public.film_actor AS fa
            INNER JOIN public.film AS film
                ON film.film_id = fa.film_id
            WHERE fa.actor_id = active_years.actor_id
              AND film.release_year > active_years.release_year
              AND film.release_year
                  <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
        ) AS next_release_year
    FROM (
        SELECT DISTINCT
            fa.actor_id,
            film.release_year
        FROM public.film_actor AS fa
        INNER JOIN public.film AS film
            ON film.film_id = fa.film_id
        WHERE film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
    ) AS active_years
) AS gaps
INNER JOIN public.actor AS actor
    ON actor.actor_id = gaps.actor_id
WHERE gaps.next_release_year IS NOT NULL
ORDER BY gap_years DESC, actor.actor_id, gaps.previous_release_year;

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
    actor.actor_id,
    actor.first_name,
    actor.last_name,
    earlier.release_year AS previous_release_year,
    MIN(later.release_year) AS next_release_year,
    MIN(later.release_year) - earlier.release_year AS gap_years
FROM public.actor AS actor
INNER JOIN (
    SELECT DISTINCT
        fa.actor_id,
        film.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS film
        ON film.film_id = fa.film_id
    WHERE film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
) AS earlier
    ON earlier.actor_id = actor.actor_id
INNER JOIN (
    SELECT DISTINCT
        fa.actor_id,
        film.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS film
        ON film.film_id = fa.film_id
    WHERE film.release_year <= EXTRACT(YEAR FROM CURRENT_DATE)::integer
) AS later
    ON later.actor_id = earlier.actor_id
   AND later.release_year > earlier.release_year
GROUP BY actor.actor_id, actor.first_name, actor.last_name, earlier.release_year
ORDER BY gap_years DESC, actor.actor_id, earlier.release_year;
