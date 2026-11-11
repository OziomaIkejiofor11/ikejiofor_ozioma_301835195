// portfolio-4-nosql/generate_complaints.js
// Generates ~12,000 complaint documents across the three complaint types. Each type carries
// its own detail sub-document (enforced by the $jsonSchema oneOf in setup_validation.js).
// Every complaint has photos[], a location, and a status_history with >=1 entry.
// Run with:  mongosh portfolio-4-nosql/generate_complaints.js
db = db.getSiblingDB("cleanroute");

const zones = ["Lekki", "Yaba", "Ikeja", "Surulere", "Independence Layout", "New Haven"];
const wasteTypes = ["general", "recyclable", "organic", "construction", "electronic"];
const severity = ["low", "medium", "high"];

function rand(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function daysAgoMs(d) { return Date.now() - d * 24 * 3600 * 1000; }

function statusHistory(baseMs, type) {
    const seq = ["open", "investigating", "resolved"];
    if (type === "illegal_dumping" && Math.random() < 0.3) seq.push("rejected");
    const n = randInt(1, seq.length);
    const hist = [];
    for (let i = 0; i < n; i++) {
        hist.push({
            status: seq[i],
            at: new Date(baseMs + i * randInt(2, 18) * 3600 * 1000),
            by: "agent-" + randInt(1, 6),
            note: (seq[i] === "resolved") ? "Closed after verification." :
                  (seq[i] === "investigating") ? "Assigned to field team." :
                  "Complaint logged by customer."
        });
    }
    return hist;
}

function photos(n) {
    const out = [];
    for (let i = 0; i < n; i++) {
        out.push({
            url: "https://cdn.cleanroute.ng/complaints/photo_" + randInt(1000, 9999) + "_" + i + ".jpg",
            caption: rand(["overflowing bin", "spilled refuse on road", "dumped construction debris",
                           "blocked drain", "broken bin lid"])
        });
    }
    return out;
}

const N_COMPLAINTS = 12000;          // ~2 years of complaints, enough for an index to matter
const docs = [];
let cid = 1000;
const zoneInfo = {
    "Lekki": { lat: 6.45, lng: 3.47, streets: ["Admiralty Way", "Lekki Phase 1 Road", "Adeola Odeku Street"] },
    "Yaba": { lat: 6.50, lng: 3.38, streets: ["Herbert Macaulay Way", "Akoka Road", "Commercial Avenue"] },
    "Ikeja": { lat: 6.60, lng: 3.34, streets: ["Allen Avenue", "Obafemi Awolowo Way", "Opebi Road"] },
    "Surulere": { lat: 6.49, lng: 3.35, streets: ["Bode Thomas Street", "Adeniran Ogunsanya Street", "Ikorodu Road"] },
    "Independence Layout": { lat: 6.45, lng: 7.51, streets: ["Independence Avenue", "Chime Avenue", "Ogui Road"] },
    "New Haven": { lat: 6.46, lng: 7.49, streets: ["New Haven Layout", "Udi Road", "Agu Eze Street"] }
};

for (let i = 0; i < N_COMPLAINTS; i++) {
    const type = rand(["missed_pickup", "spillage", "illegal_dumping", "missed_pickup", "spillage"]);
    const zone = rand(zones);
    const created = daysAgoMs(randInt(1, 730));
    const base = {
        complaint_id: "CMP-" + (cid++),
        type: type,
        customer_id: NumberInt(randInt(1, 480)),
        zone: zone,
        location: {
            address: randInt(1, 60) + " " + rand(zoneInfo[zone].streets) + ", " + zone,
            lat: zoneInfo[zone].lat + (Math.random() - 0.5) * 0.02,
            lng: zoneInfo[zone].lng + (Math.random() - 0.5) * 0.02
        },
        photos: photos(randInt(1, 3)),
        status_history: statusHistory(created, type),
        created_at: new Date(created)
    };

    if (type === "missed_pickup") {
        base.missed_pickup_details = {
            scheduled_date: new Date(created - randInt(1, 3) * 24 * 3600 * 1000),
            truck_id: NumberInt(randInt(1, 12)),
            shift_id: NumberInt(randInt(1, 630))
        };
    } else if (type === "spillage") {
        base.spillage_details = {
            severity: rand(severity),
            volume_litres: NumberInt(randInt(20, 500)),
            hazardous: Math.random() < 0.15
        };
    } else {
        base.illegal_dumping_details = {
            waste_type: rand(wasteTypes),
            estimated_volume_litres: NumberInt(randInt(100, 3000)),
            reported_by: rand(["resident", "lawma_patrol", "community_watch", "passerby"])
        };
    }
    docs.push(base);
}

// insert in batches
let inserted = 0;
for (let i = 0; i < docs.length; i += 200) {
    const r = db.complaints.insertMany(docs.slice(i, i + 200), { ordered: false });
    inserted += Object.keys(r.insertedIds).length;
}
print("complaints inserted: " + inserted);
print("complaints count   : " + db.complaints.countDocuments());
print("by type            : " + JSON.stringify(
    db.complaints.aggregate([{ $group: { _id: "$type", n: { $sum: 1 } } }]).toArray()));
