# CA Brief Summary — MIT 8103 Advanced Database Systems

**Student:** Ikejiofor Ozioma Gospel · 2026/A/MIT/0976 · MIT, Miva Open University
**Case study:** CleanRoute Waste Services (simulated private waste collection, Lagos + Enugu)

> Note on source material: the attached course-notes PDF (`Edited - MIT8103 Advanced Database
> Systems.pdf`, 154 pages) is a **scanned/image-only PDF** with no extractable text layer, so the
> session titles below follow the **topic alignment that the CA question itself defines** for each
> portfolio (Design → Query Processing → Transactions/Concurrency → NoSQL → Distributed/Cloud).
> These are the five standard study sessions of MIT 8103 and map 1-to-1 with the five portfolios.

## What the CA requires

- **Type:** Individual practical database portfolio, 40 marks, 2026/2027 First Semester.
- **Case study:** each student picks one realistic organisation and uses it consistently across all
  five portfolios. (Chosen here: **CleanRoute Waste Services**.)
- **Five portfolios (7 + 7 + 7 + 7 + 6 = 34 marks):**
  1. Database Design & Modelling — case study, ER diagram, relational schema, keys, constraints,
     normalisation.
  2. Query Processing & Optimisation — SQL queries, results, execution plans, indexing/optimisation
     evidence, brief performance analysis.
  3. Transactions & Concurrency — commit, rollback, isolation, concurrency issue + control, with
     screenshot/output evidence.
  4. NoSQL & Advanced Data Models — a NoSQL model on the same case study (document/key-value/column/
     graph), implementation evidence, suitability explanation.
  5. Distributed & Cloud Database Exercise — replication, sharding, availability, consistency or
     deployment evidence.
- **Final documentation (6 marks):** a 2–3 page summary with selected case study, GitHub link,
  screenshots/evidence, individual technical reflection, and references / AI-use declaration.
- **Page limit:** the LMS submission is a **2–3 page** documentation (not the whole codebase).
- **Submission rules:** submit on the **LMS** + keep a **private GitHub repository** that the
  assessor can open. Progressive commits expected; dumping everything at the deadline loses marks.
- **Repo naming / structure:** suggested top-level folder
  `advanced-database-portfolio/` with one folder per portfolio plus a top-level `README.md`.
- **Naming rule for the final document (this student):**
  `Ikejiofor_Ozioma_2026-A-MIT-0976_Documentation.pdf`.
- **AI use:** permitted as a learning aid, but a short **AI-Use Declaration** must state the tool,
  what it was used for, and how the output was reviewed/corrected/tested by the student. AI use does
  not remove the student's responsibility for accuracy and understanding.
- **Similarity / integrity:** individual work only; copied, inaccessible, or suspicious submissions
  may be called for a short technical verification (viva). Simply pasting screenshots or copied code
  without demonstrating understanding does **not** earn full marks.
- **Marking rubric (40):** technical correctness 8, design quality 6, practical implementation 8,
  query/performance analysis 5, advanced-concept application 5, documentation + GitHub organisation 5,
  individual reflection 3.

## Portfolio → Study Session map

| Portfolio | Title | Applies to study session |
|---|---|---|
| P1 | Database Design and Modelling | Session 1 — Conceptual modelling, ER design, relational mapping, normalisation (1NF→3NF/BCNF), integrity constraints |
| P2 | Query Processing and Optimisation | Session 2 — Query execution, EXPLAIN/ANALYZE, access paths, indexing, B-tree/GiST, statistics, cost-based optimisation |
| P3 | Transactions and Concurrency | Session 3 — ACID, isolation levels, locks, MVCC, race conditions, deadlocks, SKIP LOCKED work queues |
| P4 | NoSQL and Advanced Data Models | Session 4 — Document/time-series models, schema validation (`$jsonSchema`), aggregation pipeline, indexing, SQL vs NoSQL trade-offs |
| P5 | Distributed and Cloud Database Exercise | Session 5 — Partitioning, streaming replication, read replicas, CAP, sync vs async, data-sovereignty (NDPA 2023), offline-first edge apps |
