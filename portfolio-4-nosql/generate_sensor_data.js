// portfolio-4-nosql/generate_sensor_data.js
// Populates smart_bins (~48 bins across 6 zones) and bin_readings (15-min interval,
// ~14 days -> 48 * 96 * 14 = ~64,500 documents, comfortably above the 40k requirement).
// Run with:  mongosh portfolio-4-nosql/generate_sensor_data.js
db = db.getSiblingDB("cleanroute");

const zones = [
    { name: "Lekki",                city: "Lagos", lat: 6.45, lng: 3.47 },
    { name: "Yaba",                 city: "Lagos", lat: 6.50, lng: 3.38 },
    { name: "Ikeja",                city: "Lagos", lat: 6.60, lng: 3.34 },
    { name: "Surulere",             city: "Lagos", lat: 6.49, lng: 3.35 },
    { name: "Independence Layout",  city: "Enugu", lat: 6.45, lng: 7.51 },
    { name: "New Haven",            city: "Enugu", lat: 6.46, lng: 7.49 }
];

// ---------- smart_bins (8 per zone = 48) ----------
if (db.smart_bins.countDocuments() === 0) {
    const bins = [];
    zones.forEach(z => {
        const tag = z.name.replace(/\s+/g, "").toUpperCase().slice(0, 6);
        for (let i = 1; i <= 8; i++) {
            bins.push({
                bin_id: "BIN-" + tag + "-" + i,
                zone: z.name,
                city: z.city,
                location: {
                    address: i + " Demo Street, " + z.name,
                    lat: z.lat + (Math.random() - 0.5) * 0.02,
                    lng: z.lng + (Math.random() - 0.5) * 0.02
                },
                capacity_litres: 240,
                installed_at: new Date(Date.now() - 365 * 24 * 3600 * 1000)
            });
        }
    });
    db.smart_bins.insertMany(bins);
    print("smart_bins inserted: " + bins.length);
} else {
    print("smart_bins already populated: " + db.smart_bins.countDocuments());
}

const allBins = db.smart_bins.find().toArray();

// ---------- bin_readings (15-min interval, last 14 days) ----------
const now = Date.now();
const startMs = now - 14 * 24 * 3600 * 1000;
const intervalMs = 15 * 60 * 1000;
const totalSlots = Math.floor((now - startMs) / intervalMs);

const BATCH = 5000;
let batch = [];
let total = 0;

for (let b of allBins) {
    let fill = Math.random() * 30;           // starting fill level
    let battery = 80 + Math.random() * 20;
    for (let s = 0; s < totalSlots; s++) {
        const ts = new Date(startMs + s * intervalMs);
        const hour = ts.getHours();
        const minute = ts.getMinutes();
        // trucks empty bins around 08:00 each day -> fill drops low
        if (hour === 8 && minute === 0) {
            fill = Math.random() * 12;
        } else {
            // fill drifts up; faster during daytime (more waste dropped)
            const dayRate = (hour >= 7 && hour <= 19) ? 5.5 : 1.5;
            fill = Math.min(100, fill + Math.random() * dayRate);
        }
        // slow battery drain, tiny noise
        battery = Math.max(5, battery - 0.004 + (Math.random() - 0.5) * 0.05);

        batch.push({
            ts: ts,
            meta: { bin_id: b.bin_id, zone: b.zone, city: b.city },
            fill_level_pct: Math.round(fill * 100) / 100,
            temperature_c:  Math.round((24 + Math.random() * 14) * 100) / 100,
            battery_pct:    Math.round(battery * 100) / 100
        });
        if (batch.length >= BATCH) {
            db.bin_readings.insertMany(batch, { ordered: false });
            total += batch.length;
            batch = [];
        }
    }
}
if (batch.length > 0) {
    db.bin_readings.insertMany(batch, { ordered: false });
    total += batch.length;
}

print("bin_readings inserted: " + total);
print("bin_readings count   : " + db.bin_readings.countDocuments());
