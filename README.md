# MIT 8103 — Advanced Database Systems Portfolio

**Student:** Ikejiofor Ozioma Gospel
**Matric number:** 2026/A/MIT/0976
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 — Advanced Database Systems (First Semester CA, September 2026 Cohort)
**GitHub repository:** [GitHub link]

## Case study

**CleanRoute Waste Services** — a simulated private waste-collection company serving estates and
homes in Lagos (Lekki, Yaba, Ikeja, Surulere) and Enugu (Independence Layout, New Haven).
Households and businesses subscribe to weekly pickups on their zone's collection day, can request
on-demand pickups (after a party or renovation), and pay monthly. Trucks with crews follow routes,
weigh what they collect, and drop it at dumpsites or recycling centres.

All data in this portfolio is **invented/simulated** for academic purposes.

## Repository layout

```
advanced-database-portfolio/
├── README.md                      <- this file
├── setup.sh                       <- installs + starts PostgreSQL 16 and MongoDB 8
├── start_services.sh              <- restarts both servers after the Codespace sleeps
├── collect_results.sh             <- gathers the real run output into my_results.txt
├── CHANGES.md                     <- what was tested and fixed before the run
├── docs/
│   ├── 00_brief_summary.md        <- CA brief + portfolio-to-study-session map
│   ├── REFERENCES.md
│   └── screenshots/README.md      <- list of evidence to capture
├── portfolio-1-database-design/        (ER diagram, 3NF, constraints, bulk data)
├── portfolio-2-query-optimisation/     (8 queries, EXPLAIN before/after indexes)
├── portfolio-3-transactions-concurrency/ (claim/record transactions, race condition, isolation, deadlock)
├── portfolio-4-nosql/                  (MongoDB smart bins + complaints, validation, aggregation)
└── portfolio-5-distributed-cloud/      (partitioning, primary+replica, NDPA/CAP architecture)
```

## Quick start (GitHub Codespaces)

```bash
# 1. one-time environment setup (installs + starts PostgreSQL 16 and MongoDB 8)
bash setup.sh

# 2. run each portfolio in order (each saves its own evidence log)
bash portfolio-1-database-design/run_p1.sh        2>&1 | tee p1_output.log
bash portfolio-2-query-optimisation/run_p2.sh     2>&1 | tee p2_output.log
bash portfolio-3-transactions-concurrency/run_p3.sh 2>&1 | tee p3_output.log
bash portfolio-4-nosql/run_p4.sh                  2>&1 | tee p4_output.log
bash portfolio-5-distributed-cloud/run_p5.sh      2>&1 | tee p5_output.log

# 3. gather the real results into one file
bash collect_results.sh
```

If the Codespace has been idle, run `bash start_services.sh` first.

Each portfolio folder has its own short `README.md` with the exact commands to run, what to
screenshot, and the suggested `git commit` message.

## Honesty note

Every place that needs real output from the student's own machine is marked
`[paste real output here]` or `[paste real result]`. No EXPLAIN plans, timings, row counts or
screenshots are fabricated in this repository.
