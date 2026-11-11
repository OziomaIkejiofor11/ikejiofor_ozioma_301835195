// portfolio-4-nosql/setup_validation.js
// Creates the CleanRoute MongoDB collections:
//   - smart_bins            (reference data for the physical bins)
//   - bin_readings           (time-series: fill %, temperature, battery every 15 min)
//   - complaints             (mixed-shape documents validated with $jsonSchema oneOf)
// Run with:  mongosh portfolio-4-nosql/setup_validation.js
db = db.getSiblingDB("cleanroute");

db.smart_bins.drop();
db.bin_readings.drop();
db.complaints.drop();

// ---------- smart_bins (plain reference collection) ----------
db.createCollection("smart_bins");

// ---------- bin_readings (time-series, 15-min granularity) ----------
db.createCollection("bin_readings", {
    timeseries: {
        timeField: "ts",
        metaField: "meta",
        granularity: "minutes"
    }
});

// ---------- complaints (validated with $jsonSchema oneOf per complaint type) ----------
// MongoDB $jsonSchema supports oneOf / anyOf (NOT if/then), so each complaint type is a
// separate oneOf branch with its own required detail sub-document.
db.createCollection("complaints", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["complaint_id", "type", "customer_id", "zone", "location",
                       "status_history", "created_at"],
            properties: {
                complaint_id: { bsonType: "string" },
                type:         { enum: ["missed_pickup", "spillage", "illegal_dumping"] },
                customer_id:  { bsonType: ["int", "long"] },
                zone:         { bsonType: "string" },
                location: {
                    bsonType: "object",
                    required: ["address"],
                    properties: {
                        address: { bsonType: "string" },
                        lat:     { bsonType: ["double", "int", "long"] },
                        lng:     { bsonType: ["double", "int", "long"] }
                    }
                },
                photos: {
                    bsonType: "array",
                    items: {
                        bsonType: "object",
                        required: ["url"],
                        properties: {
                            url:     { bsonType: "string" },
                            caption: { bsonType: "string" }
                        }
                    }
                },
                status_history: {
                    bsonType: "array",
                    minItems: 1,
                    items: {
                        bsonType: "object",
                        required: ["status", "at"],
                        properties: {
                            status: { enum: ["open", "investigating", "resolved", "rejected"] },
                            at:     { bsonType: "date" },
                            by:     { bsonType: "string" },
                            note:   { bsonType: "string" }
                        }
                    }
                },
                created_at: { bsonType: "date" }
            },
            oneOf: [
                {
                    properties: {
                        type: { enum: ["missed_pickup"] },
                        missed_pickup_details: {
                            bsonType: "object",
                            required: ["scheduled_date"],
                            properties: {
                                scheduled_date: { bsonType: "date" },
                                truck_id:       { bsonType: ["int", "long"] },
                                shift_id:       { bsonType: ["int", "long"] }
                            }
                        }
                    },
                    required: ["missed_pickup_details"]
                },
                {
                    properties: {
                        type: { enum: ["spillage"] },
                        spillage_details: {
                            bsonType: "object",
                            required: ["severity"],
                            properties: {
                                severity:    { enum: ["low", "medium", "high"] },
                                volume_litres: { bsonType: ["int", "long"] },
                                hazardous:   { bsonType: "bool" }
                            }
                        }
                    },
                    required: ["spillage_details"]
                },
                {
                    properties: {
                        type: { enum: ["illegal_dumping"] },
                        illegal_dumping_details: {
                            bsonType: "object",
                            required: ["waste_type"],
                            properties: {
                                waste_type:              { bsonType: "string" },
                                estimated_volume_litres: { bsonType: ["int", "long"] },
                                reported_by:             { bsonType: "string" }
                            }
                        }
                    },
                    required: ["illegal_dumping_details"]
                }
            ]
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

print("setup_validation.js: created smart_bins, bin_readings (time-series), complaints (validated).");
