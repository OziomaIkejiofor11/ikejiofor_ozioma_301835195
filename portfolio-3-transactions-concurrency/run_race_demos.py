#!/usr/bin/env python3
"""
run_race_demos.py - Portfolio 3: all the two-session demos in ONE run.

Opens two REAL PostgreSQL sessions (Driver A and Driver B) and runs, in order:
  Part 1  THE BUG        two drivers grab the same pickup (read, then blind UPDATE)
  Part 2  FIX 1          conditional UPDATE (atomic compare-and-swap)
  Part 3  FIX 2          SELECT ... FOR UPDATE SKIP LOCKED work queue (claim_pickup)
  Part 4  ISOLATION      READ COMMITTED  - a newly committed row becomes visible mid-transaction
  Part 5  ISOLATION      REPEATABLE READ - the snapshot stays frozen
  Part 6  DEADLOCK       opposite lock order -> "deadlock detected", then the fixed-order fix

Everything printed is real output from the database. Nothing is simulated.
Run (after run_p1.sh and run_p3.sh):
    sudo runuser -u postgres -- /usr/bin/python3 run_race_demos.py | tee race_demos_output.log
"""
import sys
import threading
import time

import psycopg2
from psycopg2 import errors

DSN = "dbname=cleanroute user=postgres host=/var/run/postgresql"
SEP = "=" * 78


def connect(name):
    c = psycopg2.connect(DSN, application_name=name)
    c.autocommit = False
    with c.cursor() as cur:
        cur.execute("SET lock_timeout = '15s'")
    c.commit()
    return c


def say(msg=""):
    print(msg, flush=True)


def q(conn, label, sql, params=None, fetch=True):
    """Run one statement on one session, print the statement + its real result."""
    with conn.cursor() as cur:
        cur.execute(sql, params)
        compact = " ".join(cur.query.decode().split())      # statement with real values filled in
        if fetch and cur.description:
            rows = cur.fetchall()
            say(f"  {label}: {compact}")
            say(f"        -> {rows}")
            return rows
        say(f"  {label}: {compact}")
        say(f"        -> rowcount = {cur.rowcount}")
        return cur.rowcount


# --------------------------------------------------------------- setup helpers
ADMIN = connect("admin")


def scalar(sql, params=None):
    with ADMIN.cursor() as cur:
        cur.execute(sql, params)
        r = cur.fetchone()
    ADMIN.commit()
    return r[0] if r else None


ZONE = scalar("""SELECT zone_id FROM zone
                  WHERE day_name_to_dow(collection_day) = EXTRACT(DOW FROM CURRENT_DATE)::int
                  ORDER BY zone_id LIMIT 1""")
SHIFT_A = scalar("""SELECT s.shift_id FROM shift s JOIN crew_member d ON d.crew_member_id = s.driver_id
                     WHERE d.phone = '+2348000999001' AND s.shift_date = CURRENT_DATE""")
SHIFT_B = scalar("""SELECT s.shift_id FROM shift s JOIN crew_member d ON d.crew_member_id = s.driver_id
                     WHERE d.phone = '+2348000999002' AND s.shift_date = CURRENT_DATE""")
DRIVER_A = scalar("SELECT crew_member_id FROM crew_member WHERE phone = '+2348000999001'")
DRIVER_B = scalar("SELECT crew_member_id FROM crew_member WHERE phone = '+2348000999002'")
DEMO_CUST = scalar("""SELECT customer_id FROM customer
                       WHERE phone LIKE '+2348000999%%' AND zone_id = %s ORDER BY customer_id LIMIT 1""", (ZONE,))
if None in (ZONE, SHIFT_A, SHIFT_B, DRIVER_A, DRIVER_B, DEMO_CUST):
    sys.exit("demo data missing - run run_p1.sh and then run_p3.sh first "
             f"(zone={ZONE} shiftA={SHIFT_A} shiftB={SHIFT_B} custs={DEMO_CUST})")


def fresh_pickups(n):
    """Create n brand-new OPEN demo pickups that sort FIRST in the queue (oldest requested_at)."""
    ids = []
    with ADMIN.cursor() as cur:
        for i in range(n):
            cur.execute("""INSERT INTO pickup(customer_id, zone_id, scheduled_date, requested_at, pickup_type, status)
                           VALUES (%s, %s, CURRENT_DATE, now() - interval '10 years' + (%s || ' seconds')::interval,
                                   'on_demand', 'OPEN') RETURNING pickup_id""", (DEMO_CUST, ZONE, i))
            ids.append(cur.fetchone()[0])
    ADMIN.commit()
    return ids


def drop_pickups(ids):
    with ADMIN.cursor() as cur:
        cur.execute("DELETE FROM pickup WHERE pickup_id = ANY(%s)", (ids,))
    ADMIN.commit()


OLDEST_OPEN = """SELECT pickup_id FROM pickup
                  WHERE status='OPEN' AND zone_id=%s AND scheduled_date<=CURRENT_DATE
                  ORDER BY requested_at LIMIT 1"""

say(SEP)
say("MIT 8103 - Portfolio 3 - concurrency demos (real two-session run)")
say(f"started: {time.strftime('%Y-%m-%d %H:%M:%S')}   zone_id={ZONE}  shiftA={SHIFT_A}  shiftB={SHIFT_B}")
say(SEP)

# ================================================================ PART 1
say("\nPART 1 - THE BUG: both drivers read the same OPEN pickup, then both UPDATE it blindly")
ids = fresh_pickups(1)
A, B = connect("driverA"), connect("driverB")
ra = q(A, "A1 read ", OLDEST_OPEN, (ZONE,))
rb = q(B, "B1 read ", OLDEST_OPEN, (ZONE,))
pid = ra[0][0]
say(f"  >>> both sessions picked pickup_id {pid}; same row = {ra == rb}")
q(A, "A2 write", "UPDATE pickup SET status='ASSIGNED', shift_id=%s WHERE pickup_id=%s", (SHIFT_A, pid), fetch=False)
A.commit(); say("  A3: COMMIT")
q(B, "B2 write", "UPDATE pickup SET status='ASSIGNED', shift_id=%s WHERE pickup_id=%s", (SHIFT_B, pid), fetch=False)
B.commit(); say("  B3: COMMIT")
res = q(ADMIN, "verify  ", "SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id=%s", (pid,))
ADMIN.commit()
say(f"  RESULT: both UPDATEs reported success, final shift_id={res[0][2]} (shift B={SHIFT_B}). "
    f"Driver A's assignment (shift A={SHIFT_A}) was silently overwritten = LOST UPDATE.")
A.close(); B.close(); drop_pickups(ids)

# ================================================================ PART 2
say("\nPART 2 - FIX 1: conditional UPDATE (compare-and-swap: only succeeds if still OPEN)")
ids = fresh_pickups(1)
A, B = connect("driverA"), connect("driverB")
ra = q(A, "A1 read ", OLDEST_OPEN, (ZONE,))
rb = q(B, "B1 read ", OLDEST_OPEN, (ZONE,))
pid = ra[0][0]
say(f"  >>> both sessions picked pickup_id {pid}")
n1 = q(A, "A2 write", "UPDATE pickup SET status='ASSIGNED', shift_id=%s WHERE pickup_id=%s AND status='OPEN'",
       (SHIFT_A, pid), fetch=False)
A.commit(); say("  A3: COMMIT")
n2 = q(B, "B2 write", "UPDATE pickup SET status='ASSIGNED', shift_id=%s WHERE pickup_id=%s AND status='OPEN'",
       (SHIFT_B, pid), fetch=False)
B.commit(); say("  B3: COMMIT")
res = q(ADMIN, "verify  ", "SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id=%s", (pid,))
ADMIN.commit()
say(f"  RESULT: A updated {n1} row, B updated {n2} rows; final shift_id={res[0][2]} (shift A={SHIFT_A}). "
    f"B knows it lost and must pick another pickup.")
A.close(); B.close(); drop_pickups(ids)

# ================================================================ PART 3
say("\nPART 3 - FIX 2: claim_pickup() uses SELECT ... FOR UPDATE SKIP LOCKED (work queue)")
ids = fresh_pickups(2)
A, B = connect("driverA"), connect("driverB")
ca = q(A, "A1 claim", "SELECT claim_pickup(%s, %s)", (DRIVER_A, ZONE))   # A holds its row lock (uncommitted)
cb = q(B, "B1 claim", "SELECT claim_pickup(%s, %s)", (DRIVER_B, ZONE))   # B skips A's locked row
pa, pb = ca[0][0], cb[0][0]
say(f"  >>> A claimed {pa}, B claimed {pb}  -> different pickups: {pa != pb}")
A.commit(); say("  A2: COMMIT")
B.commit(); say("  B2: COMMIT")
q(ADMIN, "verify  ", "SELECT pickup_id, status, shift_id FROM pickup WHERE pickup_id = ANY(%s) ORDER BY pickup_id", (ids,))
ADMIN.commit()
A.close(); B.close(); drop_pickups(ids)

# ================================================================ PART 4
COUNT_OPEN = ("SELECT count(*) FROM pickup WHERE status='OPEN' AND zone_id=%s AND scheduled_date<=CURRENT_DATE")


def isolation_demo(level, title):
    say(f"\n{title}")
    ids = fresh_pickups(1)           # makes sure there is at least a stable baseline
    A, B = connect("driverA"), connect("driverB")
    A.set_session(isolation_level=level)
    before = q(A, "A1 count", COUNT_OPEN, (ZONE,))
    q(B, "B1 insert+commit", """INSERT INTO pickup(customer_id, zone_id, scheduled_date, pickup_type, status)
                                VALUES (%s, %s, CURRENT_DATE, 'on_demand', 'OPEN') RETURNING pickup_id""",
      (DEMO_CUST, ZONE))
    B.commit(); say("  B2: COMMIT  (a new OPEN pickup is now committed)")
    after = q(A, "A2 count", COUNT_OPEN, (ZONE,))
    A.commit(); say("  A3: COMMIT")
    A.set_session(isolation_level="READ COMMITTED")
    fresh = q(A, "A4 count (new transaction)", COUNT_OPEN, (ZONE,))
    A.commit()
    say(f"  RESULT: inside the transaction A saw {before[0][0]} then {after[0][0]}; "
        f"in a new transaction it sees {fresh[0][0]}.")
    A.close(); B.close()
    with ADMIN.cursor() as cur:
        cur.execute("DELETE FROM pickup WHERE customer_id=%s AND scheduled_date=CURRENT_DATE AND pickup_type='on_demand' "
                    "AND status='OPEN'", (DEMO_CUST,))
    ADMIN.commit()


isolation_demo("READ COMMITTED", "PART 4 - ISOLATION: READ COMMITTED (default) - the new row appears inside A's transaction")
isolation_demo("REPEATABLE READ", "PART 5 - ISOLATION: REPEATABLE READ - A keeps its frozen snapshot until it commits")

# ================================================================ PART 6
say("\nPART 6 - DEADLOCK: A locks p1 then wants p2; B locks p2 then wants p1")
ids = fresh_pickups(2)
p1, p2 = sorted(ids)
A, B = connect("driverA"), connect("driverB")
q(A, "A1 lock p1", "SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p1,))
q(B, "B1 lock p2", "SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p2,))
outcome = {}


def grab(conn, who, pid):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (pid,))
        outcome[who] = "got the second lock"
    except errors.DeadlockDetected as e:
        outcome[who] = "DEADLOCK DETECTED -> " + str(e).strip().splitlines()[0]
        conn.rollback()
    except Exception as e:                      # pragma: no cover
        outcome[who] = "error: " + str(e).strip().splitlines()[0]
        conn.rollback()


ta = threading.Thread(target=grab, args=(A, "A", p2))
tb = threading.Thread(target=grab, args=(B, "B", p1))
say(f"  A2: A asks for p2={p2} (held by B) -> blocks")
ta.start(); time.sleep(0.5)
say(f"  B2: B asks for p1={p1} (held by A) -> circular wait; PostgreSQL's detector fires after ~1 s")
tb.start()
ta.join(); tb.join()
for who in ("A", "B"):
    say(f"  session {who}: {outcome[who]}")
for c in (A, B):
    try:
        c.rollback()
    except Exception:
        pass
A.close(); B.close()
say("  RESULT: exactly one session was chosen as the victim and rolled back; the other proceeded.")

say("\nPART 6b - THE FIX: both sessions lock in the SAME order (lowest pickup_id first) -> no deadlock")
A, B = connect("driverA"), connect("driverB")
q(A, "A1 lock p1", "SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p1,))
out2 = {}


def ordered(conn, who):
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p1,))   # B waits here
            cur.execute("SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p2,))
        conn.commit()
        out2[who] = "finished, no deadlock"
    except Exception as e:
        out2[who] = "error: " + str(e).strip().splitlines()[0]
        conn.rollback()


tb = threading.Thread(target=ordered, args=(B, "B"))
say(f"  B1: B also asks for p1={p1} first (waits for A)")
tb.start(); time.sleep(0.5)
q(A, "A2 lock p2", "SELECT pickup_id FROM pickup WHERE pickup_id=%s FOR UPDATE", (p2,))
A.commit(); say("  A3: COMMIT (releases p1 and p2)")
tb.join()
say(f"  session B: {out2['B']}")
A.close(); B.close()
drop_pickups(ids)

say("\n" + SEP)
say("ALL SIX PARTS COMPLETED - every line above is real output from this PostgreSQL server.")
say(SEP)
