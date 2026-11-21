# SQL_DDL_Func_HW

Author: Ruta Karulaite

## Submission files

- `SQL_DDL_Func_Ruta_Karulaite_HW.sql` — Tasks 1–5, explanatory comments and rollback-only tests.
- `SQL_DDL_Func_Ruta_Karulaite_HW.txt` — Task 6: analysis of the actual exported functions, aggregate, dependent views and triggers, followed by executable replacements and tests.

## Run Tasks 1–5

Open the SQL file in pgAdmin connected to `dvdrental` and execute the entire file.
If a previous run failed inside a transaction, first run `ROLLBACK;` separately.

Base tables are in `public`; assignment objects are in `core`. A unique expression
index protects normalized movie titles. Existing objects use `CREATE OR REPLACE`
or an existence check. Definitions are committed before fixture tests.

This file has passed on the student's PostgreSQL 18 instance, including the
quarter-boundary, invalid-input, missing-data, duplicate and optional-parameter checks.

## Run Task 6 verification

The TXT starts with an explanatory SQL block comment, followed by valid SQL.
To verify it, open the TXT as plain text, copy **all** its contents into a new
pgAdmin Query Tool tab connected to `dvdrental`, and execute the entire text.

It replaces the exact existing signatures of:

- `public.rewards_report(integer, numeric)`;
- `public.get_customer_balance(integer, timestamp with time zone)`;
- `public.last_day(timestamp with time zone)`.

It also creates `core.rewards_report_for_month` with an optional month.
Function definitions are committed; all fixture data is rolled back. The fixture
checks a hand-calculated balance **increase of 84.94** above the existing-activity
baseline, exact reward thresholds, historical
cutoffs, invalid input, leap years, NULL and time-zone behavior. The final optional
month comparison must return `true`; report counts vary with the real database.

## Actual source evidence

The Task 6 analysis is based on these exports supplied by the student on 2026-11-21:

- `data-1795270692024.csv`: nine actual function bodies from `pg_get_functiondef`.
- `data-1795270906306.csv`: the `group_concat` aggregate, its three dependent views
  and fourteen `last_updated` trigger bindings.

The installed balance function uses valid `CASE`; this analysis does not claim the
invalid `IF` expression found in another DVD Rental distribution exists here.

The replacement code was additionally tested twice on PostgreSQL 18.7 via PGlite
using those exported function definitions and a reproduced partitioned/timestamptz
schema with sample data. Production-scale performance and multi-session behavior
were not benchmarked. Task 6 still needs the final run on the student's live instance.

## Compatibility and rollback behavior

`payment_date`, `rental_date` and `return_date` use time zones in the student's
instance. `payment` is range-partitioned. Boundary tests create a DEFAULT partition
inside the fixture transaction only if needed; ROLLBACK removes it automatically.
Existing ranges are not changed. Creating a child partition needs parent-owner
permissions and may lock the parent. Tests also verify payment counts/totals are
unchanged and the fixture partition no longer exists. Tasks 1–5 can advance
sequences when generating fixture IDs; ID gaps after rollback are normal.
The revised Task 6 fixture reuses existing rows and does not request IDs, so even
stale sequences do not cause a duplicate-key error. It does not reset sequences.

The stock function reports the latest **historical** customer/rental date for each
available inventory copy. The output rental date is explicitly converted to the
session-local timestamp, preserving its existing return signature.

`new_movie` defaults to the current year and Klingon, but validates that the language
exists. Missing Klingon raises an explicit error. Tests add it only temporarily.

## GitHub

Task folder: `SQL_DDL_Func_HW/`  
Branch: `SQL_DDL_Func_HW`  
Pull request title: `SQL_DDL_Func_HW`

Repository: https://github.com/karuruta/DAE_Introduction


## v4 fixture update

The student's customer sequence suggested existing ID 1 during Task 6 testing.
The revised fixture inserts no customer, inventory, film, rental or payment rows.
It temporarily updates selected existing rows, measures a baseline for other
customer activity, checks a balance increase of 84.94, and rolls all changes back.
A separate regression test deliberately set five sequences to existing ID 1 in
an isolated database: two full runs passed without consuming/changing any sequence.
The live student's sequences are never reset by the submitted code.
