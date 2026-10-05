-- ICT371 Scenario 3: Student Hostel Room Allocation
-- Run each numbered step separately (highlight + F5) so every screenshot is clear.
-- Notices (RAISE NOTICE) appear in the "Messages" tab.

-- ========== STEP 1: Tables and data ==========
DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0),
    ('B202', 6);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- ========== STEP 2: IF / ELSIF / ELSE ==========
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % : FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % : ONE SPACE LEFT', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % : SEVERAL SPACES (%)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- ========== STEP 3: WHILE and numeric FOR ==========
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check %', i;
    END LOOP;
END $$;

-- ========== STEP 4: allocate_room procedure ==========
CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id        INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank.';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist.', p_room_id;
    END IF;

    IF v_available < 1 THEN
        RAISE NOTICE 'Allocation REJECTED for student %: room % is full.',
                     p_student_number, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id)
    VALUES (p_student_number, p_room_id);

    RAISE NOTICE 'Student % allocated to room %.', p_student_number, p_room_id;
END $$;

-- ========== STEP 5: Two valid allocations + one to a full room ==========
CALL allocate_room('2024001', 1);   -- valid
CALL allocate_room('2024002', 2);   -- valid (last space in A102)
CALL allocate_room('2024003', 3);   -- B201 is full

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ========== STEP 6: check_out procedure (called twice for allocation 1) ==========
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist.', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out. No space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. One bed space released.', p_allocation_id;
END $$;

CALL check_out(1);   -- frees one space
CALL check_out(1);   -- must NOT free another

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ========== STEP 7: Explicit cursor (full or nearly full rooms) ==========
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_number, available_spaces FROM hostel_rooms
        WHERE available_spaces <= 1 ORDER BY available_spaces, room_number;
    v_room   VARCHAR;
    v_spaces INT;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_room, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', v_room;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)', v_room, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- ========== STEP 8: Blank student number handled with EXCEPTION ==========
DO $$
BEGIN
    CALL allocate_room('', 1);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ========== STEP 9: Final state ==========
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
