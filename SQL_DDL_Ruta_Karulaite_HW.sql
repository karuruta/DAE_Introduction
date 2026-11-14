-- Recruitment Agency | Ruta Karulaite
-- Run with psql from the postgres maintenance database, with CREATE DATABASE
-- privileges: psql -X -d postgres -f SQL_DDL_Ruta_Karulaite_HW.sql
-- Database creation runs outside a transaction; the rest is atomic.
\set ON_ERROR_STOP on
SELECT 'CREATE DATABASE recruitment_agency'
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'recruitment_agency'
)
\gexec
\connect recruitment_agency

BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE SCHEMA IF NOT EXISTS recruitment;
SET LOCAL search_path TO recruitment, pg_catalog;

-- Parent tables come first: a REFERENCES clause requires its target to exist
-- or CREATE TABLE fails with "relation does not exist". Without foreign keys,
-- orphan records could point to missing candidates, jobs or recruiters.
-- bigint identity avoids manual ID collisions and gives IDs room to grow.
-- Child keys use the same types; version numbers are integers, not fractions.
-- Text preserves leading zeros and punctuation in phone and registration
-- numbers. Boolean prevents free-text variants of active/inactive.
-- Numeric preserves exact cents; floating point can introduce rounding errors.
-- Date stores calendar days; timestamptz preserves an instant across time zones.
-- PRIMARY KEY identifies each row. UNIQUE prevents duplicate business keys
-- and duplicate candidate/job applications; NOT NULL prevents missing required
-- values such as a candidate's email or an application's recruiter.

CREATE TABLE IF NOT EXISTS candidate (
    candidate_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name text NOT NULL,
    email text NOT NULL UNIQUE,
    phone text
);

CREATE TABLE IF NOT EXISTS company (
    company_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    registration_no text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS recruiter (
    recruiter_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name text NOT NULL,
    email text NOT NULL UNIQUE,
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS skill (
    skill_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS company_contact (
    contact_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id bigint NOT NULL REFERENCES company (company_id),
    full_name text NOT NULL,
    email text NOT NULL,
    role_title text NOT NULL
);

CREATE TABLE IF NOT EXISTS job (
    job_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id bigint NOT NULL REFERENCES company (company_id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_version (
    job_id bigint REFERENCES job (job_id),
    version_no integer,
    effective_at timestamptz NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    location_label text NOT NULL,
    salary_min_eur numeric(12,2),
    salary_max_eur numeric(12,2),
    status text NOT NULL,
    PRIMARY KEY (job_id, version_no),
    -- Version numbering starts at 1; zero and negative numbers are invalid.
    CONSTRAINT job_version_positive CHECK (version_no > 0),
    -- An optional salary range may be unknown but cannot be negative or reversed.
    CONSTRAINT job_salary_min_nonnegative CHECK (salary_min_eur >= 0),
    CONSTRAINT job_salary_max_valid CHECK (
        salary_max_eur >= 0 AND salary_max_eur >= salary_min_eur
    ),
    -- Reject unsupported job statuses rather than silently hiding them from reports.
    CONSTRAINT job_status_allowed CHECK (status IN ('open', 'on_hold', 'closed'))
);

CREATE TABLE IF NOT EXISTS application (
    application_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_id bigint NOT NULL REFERENCES candidate (candidate_id),
    job_id bigint NOT NULL,
    version_no integer NOT NULL,
    recruiter_id bigint NOT NULL REFERENCES recruiter (recruiter_id),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (candidate_id, job_id),
    FOREIGN KEY (job_id, version_no) REFERENCES job_version (job_id, version_no)
);

CREATE TABLE IF NOT EXISTS application_stage_event (
    application_id bigint REFERENCES application (application_id),
    changed_at timestamptz,
    stage text NOT NULL,
    note text,
    PRIMARY KEY (application_id, changed_at),
    -- Only known workflow stages may appear in the application history.
    CONSTRAINT application_stage_allowed CHECK (
        stage IN ('submitted', 'screening', 'interview', 'offered', 'hired', 'rejected', 'withdrawn')
    )
);

CREATE TABLE IF NOT EXISTS interview (
    interview_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id bigint NOT NULL REFERENCES application (application_id),
    recruiter_id bigint NOT NULL REFERENCES recruiter (recruiter_id),
    contact_id bigint REFERENCES company_contact (contact_id),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    status text NOT NULL,
    venue text NOT NULL,
    feedback text,
    -- Reject zero or negative interview durations and unknown scheduling states.
    CONSTRAINT interview_times_ordered CHECK (ends_at > starts_at),
    CONSTRAINT interview_status_allowed CHECK (status IN ('scheduled', 'completed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS placement (
    placement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id bigint NOT NULL UNIQUE REFERENCES application (application_id),
    start_date date NOT NULL,
    end_date date,
    annual_salary_eur numeric(12,2) NOT NULL,
    status text NOT NULL,
    -- The assignment's date floor applies to placement starts; it rejects
    -- legacy or placeholder dates, including 2000-01-01 itself.
    CONSTRAINT placement_start_after_2000 CHECK (start_date > DATE '2000-01-01'),
    -- An end date cannot precede the start, and a placement salary must be positive.
    CONSTRAINT placement_dates_ordered CHECK (end_date >= start_date),
    CONSTRAINT placement_salary_positive CHECK (annual_salary_eur > 0),
    -- Keep placement reports consistent by rejecting unrecognized states.
    CONSTRAINT placement_status_allowed CHECK (status IN ('planned', 'active', 'ended', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS candidate_skill (
    candidate_id bigint REFERENCES candidate (candidate_id),
    skill_id bigint REFERENCES skill (skill_id),
    proficiency text NOT NULL,
    PRIMARY KEY (candidate_id, skill_id),
    -- Prevent unsupported proficiency labels from distorting skill searches.
    CONSTRAINT candidate_skill_proficiency_allowed CHECK (
        proficiency IN ('beginner', 'intermediate', 'advanced', 'expert')
    )
);

CREATE TABLE IF NOT EXISTS work_experience (
    experience_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_id bigint NOT NULL REFERENCES candidate (candidate_id),
    employer_name text NOT NULL,
    job_title text NOT NULL,
    start_date date NOT NULL,
    end_date date,
    -- NULL means ongoing; a supplied end date must follow or equal the start.
    CONSTRAINT work_experience_dates_ordered CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS location_preference (
    candidate_id bigint REFERENCES candidate (candidate_id),
    location_label text,
    PRIMARY KEY (candidate_id, location_label)
);

CREATE TABLE IF NOT EXISTS candidate_service (
    service_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_id bigint NOT NULL REFERENCES candidate (candidate_id),
    recruiter_id bigint NOT NULL REFERENCES recruiter (recruiter_id),
    service_type text NOT NULL,
    scheduled_at timestamptz NOT NULL,
    status text NOT NULL,
    fee_eur numeric(10,2) NOT NULL DEFAULT 0,
    result_note text,
    -- Prevent unknown service types/states and negative charges in fee totals.
    CONSTRAINT service_type_allowed CHECK (service_type IN ('cv_review', 'career_coaching', 'mock_interview')),
    CONSTRAINT service_status_allowed CHECK (status IN ('scheduled', 'completed', 'cancelled')),
    CONSTRAINT service_fee_nonnegative CHECK (fee_eur >= 0)
);

-- Primary and unique constraints already index their keys. Index foreign keys
-- where they are not the leading columns of an existing suitable index.
CREATE INDEX IF NOT EXISTS ix_company_contact_company_id ON company_contact (company_id);
CREATE INDEX IF NOT EXISTS ix_job_company_id ON job (company_id);
CREATE INDEX IF NOT EXISTS ix_application_job_id ON application (job_id, version_no);
CREATE INDEX IF NOT EXISTS ix_application_recruiter_id ON application (recruiter_id);
CREATE INDEX IF NOT EXISTS ix_interview_application_id ON interview (application_id);
CREATE INDEX IF NOT EXISTS ix_interview_recruiter_id ON interview (recruiter_id);
CREATE INDEX IF NOT EXISTS ix_interview_contact_id ON interview (contact_id);
CREATE INDEX IF NOT EXISTS ix_candidate_skill_skill_id ON candidate_skill (skill_id);
CREATE INDEX IF NOT EXISTS ix_work_experience_candidate_id ON work_experience (candidate_id);
CREATE INDEX IF NOT EXISTS ix_candidate_service_candidate_id ON candidate_service (candidate_id);
CREATE INDEX IF NOT EXISTS ix_candidate_service_recruiter_id ON candidate_service (recruiter_id);

-- Demo fixtures: fixed dates and business keys identify the same rows on a
-- rerun. We look up generated IDs from their parent records and insert in
-- dependency order. The two example applications follow the same timeline:
-- job published, candidate applies, interview held, placement starts.
-- The .example domain is reserved for documentation.
SELECT pg_advisory_xact_lock(hashtext('recruitment.demo_seed')::bigint);

INSERT INTO candidate (full_name, email, phone)
VALUES ('Austeja Vale', 'austeja@example.com', '+37060001001'),
       ('Matas Lake', 'matas@example.com', '+37060001002')
ON CONFLICT (email) DO NOTHING;

INSERT INTO recruiter (full_name, email)
VALUES ('Ieva Reed', 'ieva@example.com'),
       ('Tomas Wood', 'tomas@example.com')
ON CONFLICT (email) DO NOTHING;

INSERT INTO company (name, registration_no)
VALUES ('Amber Metrics', 'DEMO-001'),
       ('Baltic Supply', 'DEMO-002')
ON CONFLICT (registration_no) DO NOTHING;

INSERT INTO skill (name)
VALUES ('SQL'), ('Power BI')
ON CONFLICT (name) DO NOTHING;

-- The local view centralizes fixture values and is dropped before commit.
-- It is not part of the persistent data model.
CREATE TEMP VIEW demo_recruitment AS
SELECT v.*,
       TIMESTAMPTZ '2026-02-02 09:00+00' + v.n * INTERVAL '1 day' AS opened_at
FROM (VALUES
    (1, 'austeja@example.com', 'ieva@example.com', 'DEMO-001',
     'mira@amber.example', 'Mira North', 'Data Analyst', 'Vilnius', 'SQL'),
    (2, 'matas@example.com', 'tomas@example.com', 'DEMO-002',
     'lina@baltic.example', 'Lina Shore', 'BI Analyst', 'Kaunas', 'Power BI')
) AS v(n, candidate_email, recruiter_email, registration_no,
       contact_email, contact_name, job_title, city, skill_name);

INSERT INTO company_contact (company_id, full_name, email, role_title)
SELECT c.company_id, d.contact_name, d.contact_email, 'Hiring Manager'
FROM pg_temp.demo_recruitment AS d
JOIN company AS c USING (registration_no)
WHERE NOT EXISTS (
    SELECT 1 FROM company_contact AS cc
    WHERE cc.company_id = c.company_id AND cc.email = d.contact_email
);

INSERT INTO job (company_id, created_at)
SELECT c.company_id, d.opened_at
FROM pg_temp.demo_recruitment AS d
JOIN company AS c USING (registration_no)
WHERE NOT EXISTS (
    SELECT 1 FROM job AS j
    WHERE j.company_id = c.company_id AND j.created_at = d.opened_at
);

CREATE TEMP VIEW demo_recruitment_keys AS
SELECT d.*, ca.candidate_id, r.recruiter_id, sk.skill_id,
       (SELECT min(j.job_id) FROM job AS j
        WHERE j.company_id = c.company_id AND j.created_at = d.opened_at) AS job_id,
       (SELECT min(cc.contact_id) FROM company_contact AS cc
        WHERE cc.company_id = c.company_id AND cc.email = d.contact_email) AS contact_id
FROM pg_temp.demo_recruitment AS d
JOIN candidate AS ca ON ca.email = d.candidate_email
JOIN recruiter AS r ON r.email = d.recruiter_email
JOIN skill AS sk ON sk.name = d.skill_name
JOIN company AS c USING (registration_no);

INSERT INTO job_version (job_id, version_no, effective_at, title, description,
                         location_label, salary_min_eur, salary_max_eur, status)
SELECT job_id, ver, opened_at + (ver - 1) * INTERVAL '1 day', job_title,
       'Prepare reports and validate business metrics.', city,
       32000 + 1000 * ver, 46000, 'open'
FROM pg_temp.demo_recruitment_keys
CROSS JOIN generate_series(1, 2) AS versions(ver)
ON CONFLICT (job_id, version_no) DO NOTHING;

INSERT INTO application (candidate_id, job_id, version_no, recruiter_id, submitted_at)
SELECT candidate_id, job_id, 2, recruiter_id, opened_at + INTERVAL '2 days'
FROM pg_temp.demo_recruitment_keys
ON CONFLICT (candidate_id, job_id) DO NOTHING;

CREATE TEMP VIEW demo_recruitment_applications AS
SELECT d.*, a.application_id
FROM pg_temp.demo_recruitment_keys AS d
JOIN application AS a USING (candidate_id, job_id);

INSERT INTO application_stage_event (application_id, changed_at, stage)
SELECT application_id, opened_at + e.elapsed, e.stage
FROM pg_temp.demo_recruitment_applications
CROSS JOIN (VALUES
    (INTERVAL '2 days', 'submitted'), (INTERVAL '7 days', 'interview'),
    (INTERVAL '10 days', 'hired')
) AS e(elapsed, stage)
ON CONFLICT (application_id, changed_at) DO NOTHING;

INSERT INTO interview (application_id, recruiter_id, contact_id, starts_at,
                       ends_at, status, venue)
SELECT application_id, recruiter_id, contact_id, opened_at + INTERVAL '7 days',
       opened_at + INTERVAL '7 days 1 hour', 'completed', 'Video call'
FROM pg_temp.demo_recruitment_applications AS d
WHERE NOT EXISTS (
    SELECT 1 FROM interview AS i
    WHERE i.application_id = d.application_id
      AND i.starts_at = d.opened_at + INTERVAL '7 days'
);

INSERT INTO placement (application_id, start_date, annual_salary_eur, status)
SELECT application_id, (opened_at + INTERVAL '21 days')::date, 38000, 'active'
FROM pg_temp.demo_recruitment_applications
ON CONFLICT (application_id) DO NOTHING;

INSERT INTO candidate_skill (candidate_id, skill_id, proficiency)
SELECT candidate_id, skill_id, 'advanced'
FROM pg_temp.demo_recruitment_keys
ON CONFLICT (candidate_id, skill_id) DO NOTHING;

INSERT INTO work_experience (candidate_id, employer_name, job_title, start_date, end_date)
SELECT candidate_id, 'Demo Analytics ' || n, 'Junior Analyst',
       DATE '2023-01-09', DATE '2025-12-31'
FROM pg_temp.demo_recruitment_keys AS d
WHERE NOT EXISTS (
    SELECT 1 FROM work_experience AS w
    WHERE w.candidate_id = d.candidate_id
      AND w.employer_name = 'Demo Analytics ' || d.n
      AND w.job_title = 'Junior Analyst' AND w.start_date = DATE '2023-01-09'
);

INSERT INTO location_preference (candidate_id, location_label)
SELECT candidate_id, city
FROM pg_temp.demo_recruitment_keys
ON CONFLICT (candidate_id, location_label) DO NOTHING;

INSERT INTO candidate_service (candidate_id, recruiter_id, service_type, scheduled_at, status)
SELECT candidate_id, recruiter_id, 'cv_review', opened_at - INTERVAL '1 day', 'completed'
FROM pg_temp.demo_recruitment_keys AS d
WHERE NOT EXISTS (
    SELECT 1 FROM candidate_service AS cs
    WHERE cs.candidate_id = d.candidate_id AND cs.service_type = 'cv_review'
      AND cs.scheduled_at = d.opened_at - INTERVAL '1 day'
);

DROP VIEW pg_temp.demo_recruitment_applications;
DROP VIEW pg_temp.demo_recruitment_keys;
DROP VIEW pg_temp.demo_recruitment;

-- The assignment requires this technical field on all tables. On the first
-- run ADD COLUMN gives existing rows the default date; subsequent runs keep
-- their original values and use the default for newly inserted rows.
ALTER TABLE candidate ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE company ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE recruiter ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE skill ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE company_contact ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE job ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE job_version ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE application ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE application_stage_event ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE interview ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE placement ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE candidate_skill ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE work_experience ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE location_preference ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE candidate_service ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT CURRENT_DATE;

-- Confirm that every existing row has a record date and every table has
-- at least two rows. These checks also run after each repeat execution.
WITH checks AS (
    SELECT 'candidate' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM candidate
    UNION ALL
    SELECT 'company' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM company
    UNION ALL
    SELECT 'recruiter' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM recruiter
    UNION ALL
    SELECT 'skill' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM skill
    UNION ALL
    SELECT 'company_contact' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM company_contact
    UNION ALL
    SELECT 'job' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM job
    UNION ALL
    SELECT 'job_version' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM job_version
    UNION ALL
    SELECT 'application' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM application
    UNION ALL
    SELECT 'application_stage_event' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM application_stage_event
    UNION ALL
    SELECT 'interview' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM interview
    UNION ALL
    SELECT 'placement' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM placement
    UNION ALL
    SELECT 'candidate_skill' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM candidate_skill
    UNION ALL
    SELECT 'work_experience' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM work_experience
    UNION ALL
    SELECT 'location_preference' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM location_preference
    UNION ALL
    SELECT 'candidate_service' AS table_name, count(*) AS row_count,
           count(*) FILTER (WHERE record_ts IS NULL) AS missing_record_ts,
           min(record_ts) AS first_record_ts, max(record_ts) AS last_record_ts
    FROM candidate_service
)
SELECT * FROM (
    SELECT * FROM checks
    UNION ALL
    SELECT 'TOTAL', sum(row_count), sum(missing_record_ts),
           min(first_record_ts), max(last_record_ts)
    FROM checks
) AS results
ORDER BY (table_name = 'TOTAL'), table_name;

COMMIT;
