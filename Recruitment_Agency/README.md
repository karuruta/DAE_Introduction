Recruitment Agency database model and documentation.

# Recruitment Agency — Physical Database

The corrected logical model separates candidates and companies into
`candidate` and `company`. Applications reference candidates, and job
postings reference companies. The `recruiter` table links agency staff
to applications, interviews and candidate services.

Job versions preserve the terms that applied when a candidate submitted
an application. Application stage events record how the application
progressed. The `candidate_skill` table links candidates and skills
in a many-to-many relationship.

[Corrected logical model](DB_Ruta_Karulaite_HW_Recruitment_Agency_Corrected.png)
