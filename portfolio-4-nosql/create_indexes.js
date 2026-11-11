// portfolio-4-nosql/create_indexes.js
// Creates indexes that move query plans from COLLSCAN (collection scan) to IXSCAN.
// For each, we run an explain() BEFORE and AFTER to show the stage change.
// Run with:  mongosh portfolio-4-nosql/create_indexes.js
db = db.getSiblingDB("cleanroute");

// Collect every "stage" name in an explain() output (works for find, aggregate and the
// time-series bucket plans, whatever the nesting), in order, without repeats.
function plain(node, depth) {
    return node !== null && typeof node === "object" && depth < 14 &&
           (Array.isArray(node) || Object.getPrototypeOf(node) === Object.prototype);
}
function collectStages(node, acc, depth = 0) {
    if (!plain(node, depth)) return acc;
    if (typeof node.stage === "string" && acc[acc.length - 1] !== node.stage) acc.push(node.stage);
    Object.keys(node).forEach(k => { if (k !== "slotBasedPlan") collectStages(node[k], acc, depth + 1); });
    return acc;
}
// Find the first numeric value stored under a given key anywhere in the explain output.
function findKey(node, key, depth = 0) {
    if (!plain(node, depth)) return undefined;
    if (typeof node[key] === "number") return node[key];
    for (const k of Object.keys(node)) { const v = findKey(node[k], key, depth + 1); if (v !== undefined) return v; }
    return undefined;
}
// Run explain("executionStats") and print: stages, docs examined, docs returned, time.
function report(label, runExplain) {
    let raw = runExplain();
    if (raw && typeof raw.finish === "function") raw = raw.finish();          // explainable cursor (find)
    else if (raw && typeof raw.toArray === "function") raw = raw.toArray()[0];
    const ex = JSON.parse(JSON.stringify(raw));                               // plain JSON copy (safe to walk)
    const stages = collectStages(ex.queryPlanner ? ex.queryPlanner.winningPlan : ex, []);
    const es = ex.executionStats || ex;
    print(label + "  stages: " + stages.join(" -> "));
    print("        totalDocsExamined=" + findKey(es, "totalDocsExamined") +
          "  totalKeysExamined=" + findKey(es, "totalKeysExamined") +
          "  nReturned=" + findKey(es, "nReturned") +
          "  executionTimeMillis=" + findKey(es, "executionTimeMillis"));
}

// ---------- query 1: latest readings for a single bin (by meta.bin_id + ts) ----------
const q1 = [{ $match: { "meta.bin_id": "BIN-LEKKI-1" } },
            { $sort: { ts: -1 } },
            { $limit: 1 }];

print("\n==== Q1 BEFORE index: explain() ====");
report("  ", () => db.bin_readings.explain("executionStats").aggregate(q1));

db.bin_readings.createIndex({ "meta.bin_id": 1, ts: -1 });

print("\n==== Q1 AFTER index: explain() ====");
report("  ", () => db.bin_readings.explain("executionStats").aggregate(q1));

// ---------- query 2: complaints by zone + type ----------
const q2 = { zone: "Lekki", type: "spillage" };

print("\n==== Q2 BEFORE index: explain() ====");
report("  ", () => db.complaints.explain("executionStats").find(q2));

db.complaints.createIndex({ zone: 1, type: 1 });

print("\n==== Q2 AFTER index: explain() ====");
report("  ", () => db.complaints.explain("executionStats").find(q2));

// ---------- query 3: complaints created in the last 30 days ----------
const q3 = { created_at: { $gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) } };

print("\n==== Q3 BEFORE index: explain() ====");
report("  ", () => db.complaints.explain("executionStats").find(q3));

db.complaints.createIndex({ created_at: -1 });

print("\n==== Q3 AFTER index: explain() ====");
report("  ", () => db.complaints.explain("executionStats").find(q3));

// ---------- query 4: bin readings in a zone over a time window (meta.zone + ts) ----------
const q4 = [{ $match: { "meta.zone": "Ikeja",
                        ts: { $gte: new Date(Date.now() - 24 * 3600 * 1000) } } },
            { $group: { _id: null, avg_fill: { $avg: "$fill_level_pct" } } }];

print("\n==== Q4 BEFORE index: explain() ====");
report("  ", () => db.bin_readings.explain("executionStats").aggregate(q4));

db.bin_readings.createIndex({ "meta.zone": 1, ts: -1 });

print("\n==== Q4 AFTER index: explain() ====");
report("  ", () => db.bin_readings.explain("executionStats").aggregate(q4));

print("\n==== indexes on bin_readings ====");
printjson(db.bin_readings.getIndexes());
print("\n==== indexes on complaints ====");
printjson(db.complaints.getIndexes());
