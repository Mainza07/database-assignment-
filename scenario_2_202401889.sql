-- ICT371 Scenario 2: Computer Laboratory Reservations
-- Run each numbered step separately (highlight + F5) so every screenshot is clear.
-- Notices (RAISE NOTICE) appear in the "Messages" tab.

-- ========== STEP 1: Tables and data ==========
DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

CREATE TABLE lab_sessions (
    session_id              SERIAL PRIMARY KEY,
    session_name            VARCHAR(100) NOT NULL,
    available_workstations  INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    lecturer        VARCHAR(100) NOT NULL,
    session_id      INT NOT NULL REFERENCES lab_sessions(session_id),
    workstations    INT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Lab A', 30),
    ('Tuesday 10:00 - Lab A', 5),
    ('Wednesday 14:00 - Lab B', 0),
    ('Thursday 09:00 - Lab B', 25);

SELECT * FROM lab_sessions ORDER BY session_id;

-- ========== STEP 2: IF / ELSIF / ELSE ==========
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : ENOUGH WORKSTATIONS (% available)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- ========== STEP 3: WHILE and numeric FOR ==========
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', i;
    END LOOP;
END $$;

-- ========== STEP 4: reserve_workstations procedure ==========
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_lecturer   VARCHAR,
    p_session_id INT,
    p_quantity   INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: %. Must be greater than zero.', p_quantity;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist.', p_session_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available.',
                     p_lecturer, p_quantity, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_quantity
    WHERE session_id = p_session_id;

    INSERT INTO reservations (lecturer, session_id, workstations)
    VALUES (p_lecturer, p_session_id, p_quantity);

    RAISE NOTICE 'Reservation recorded for %: % workstations in session %.',
                 p_lecturer, p_quantity, p_session_id;
END $$;

-- ========== STEP 5: Two valid reservations + one exceeding capacity ==========
CALL reserve_workstations('Dr. Banda', 1, 20);    -- valid
CALL reserve_workstations('Mr. Phiri', 2, 3);     -- valid
CALL reserve_workstations('Ms. Zulu', 2, 10);     -- exceeds capacity

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ========== STEP 6: cancel_reservation procedure (called twice for reservation 1) ==========
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist.', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. Nothing released.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstations released.', p_reservation_id, v_qty;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ========== STEP 7: Explicit cursor (sessions with few workstations left) ==========
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name  VARCHAR;
    v_avail INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations remaining: % (% left)', v_name, v_avail;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ========== STEP 8: Zero workstations handled with EXCEPTION ==========
DO $$
BEGIN
    CALL reserve_workstations('Dr. Mwale', 1, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ========== STEP 9: Final state ==========
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
