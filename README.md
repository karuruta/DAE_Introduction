# Recruitment Agency — Physical Database

This PostgreSQL assignment is based on the [corrected Recruitment Agency data model](DB_Ruta_Karulaite_HW_Recruitment_Agency_diagram_upd.png). The model covers candidates, client companies, job openings, applications, interviews, placements, and services provided by the agency.

## Changes made after the review

- Replaced the generic `party` entity with separate `candidate` and `company` tables. Applications reference candidates, while jobs and company contacts reference companies. These foreign keys make the intended roles explicit.
- Added a `recruiter` table. Each application, interview, and candidate service references the recruiter responsible for it. An interview can also reference an optional company contact.
- Removed the two time dimensions and revision chains from the general workflow. History is retained where it serves a clear purpose: `job_version` records changes to job details, and `application_stage_event` records changes to an application's stage.
- Grouped related tables in the diagram so that the candidate, company, and application relationships are easier to follow.

## Main relationships

| Relationship | How it is represented |
| --- | --- |
| Candidates and skills | `candidate_skill` implements the many-to-many relationship and stores proficiency for each candidate and skill pair. |
| Companies and job openings | Each `job` belongs to one company. A job can have multiple versions, identified by `(job_id, version_no)`. |
| Candidates and applications | Each application belongs to one candidate and references the exact job version through a composite foreign key. The unique constraint on `(candidate_id, job_id)` allows one application per candidate per job. |
| Applications and outcomes | An application can have multiple stage events and interviews, and at most one placement. |

## Data integrity

Candidate, recruiter, and company details are stored separately and referenced by keys. Job details belong to a specific job version, and skill proficiency belongs to the candidate and skill pair. This avoids repeating those details across applications and interviews.

The model uses `date` for calendar dates, `timestamptz` for events, and `numeric` for fees and salaries. Check constraints reject invalid values such as negative fees, unsupported statuses, and interviews that end before or at their start time. The physical database adds the assignment's technical `record_ts` column to each table as `date NOT NULL DEFAULT CURRENT_DATE`.

## Run and verify

Run the single SQL file with a PostgreSQL role that can create databases:

```sh
psql -X -d postgres -f SQL_DDL_Ruta_Karulaite_HW.sql
```

Add your local host, port, or user options if needed. The script creates the
`recruitment_agency` database if it is missing, connects to it, and then builds
and loads the `recruitment` schema. On a clean database the verification query
reports 36 rows across 15 tables, with zero missing `record_ts` values. Running
the script again leaves those counts unchanged.

In DBeaver, SQL Editor does not execute the psql backslash commands. Create
`recruitment_agency` once by running `CREATE DATABASE recruitment_agency;`
on the maintenance connection with auto-commit enabled. Open a new SQL editor
connected to `recruitment_agency`, then execute the script from `BEGIN;`
through `COMMIT;` as a SQL script.
