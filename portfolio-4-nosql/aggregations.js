// portfolio-4-nosql/aggregations.js
// Three analytical aggregations on the CleanRoute MongoDB data.
// Run with:  mongosh portfolio-4-nosql/aggregations.js
db = db.getSiblingDB("cleanroute");

print("\n==== A1: bins currently over 80% full, by zone ====");
// "currently" = the latest reading per bin in the last 2 hours that is > 80%.
const a1 = db.bin_readings.aggregate([
    { $match: { ts: { $gte: new Date(Date.now() - 2 * 3600 * 1000) } } },
    { $sort: { ts: -1 } },
    { $group: {
        _id: "$meta.bin_id",
        zone: { $first: "$meta.zone" },
        latest_fill: { $first: "$fill_level_pct" },
        ts: { $first: "$ts" }
    }},
    { $match: { latest_fill: { $gt: 80 } } },
    { $group: { _id: "$zone", bins_over_80: { $sum: 1 }, max_fill: { $max: "$latest_fill" } } },
    { $sort: { bins_over_80: -1 } }
]).toArray();
printjson(a1);

print("\n==== A2: average fill rate per day (all bins) ====");
const a2 = db.bin_readings.aggregate([
    { $group: {
        _id: { $dateToString: { format: "%Y-%m-%d", date: "$ts" } },
        avg_fill_pct: { $avg: "$fill_level_pct" },
        readings: { $sum: 1 }
    }},
    { $sort: { _id: 1 } }
]).toArray();
printjson(a2);

print("\n==== A3: complaints per zone and type ====");
const a3 = db.complaints.aggregate([
    { $group: {
        _id: { zone: "$zone", type: "$type" },
        complaints: { $sum: 1 }
    }},
    { $sort: { "_id.zone": 1, "_id.type": 1 } }
]).toArray();
printjson(a3);

print("\n==== A4 (bonus): spillage complaints that are hazardous, by severity ====");
const a4 = db.complaints.aggregate([
    { $match: { type: "spillage", "spillage_details.hazardous": true } },
    { $group: { _id: "$spillage_details.severity", n: { $sum: 1 } } },
    { $sort: { _id: 1 } }
]).toArray();
printjson(a4);
