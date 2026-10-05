-- ICT371 Scenario 4: Campus Clinic Medicine Dispensing
-- Run each numbered step separately (highlight + F5) so every screenshot is clear.
-- Notices (RAISE NOTICE) appear in the "Messages" tab.

-- ========== STEP 1: Tables and data ==========
DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    quantity       INT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 15),
    ('Ibuprofen 400mg', 0),
    ('Oral Rehydration Salts', 60);

SELECT * FROM medicines ORDER BY medicine_id;

-- ========== STEP 2: IF / ELSIF / ELSE ==========
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 20 THEN
            RAISE NOTICE '% : LOW ON STOCK (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- ========== STEP 3: WHILE and numeric FOR ==========
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Stock review day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', i;
    END LOOP;
END $$;

-- ========== STEP 4: dispense_medicine procedure ==========
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_student_number VARCHAR,
    p_medicine_id    INT,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: %. Must be greater than zero.', p_quantity;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist.', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE NOTICE 'Dispensing REJECTED for student %: requested %, only % in stock.',
                     p_student_number, p_quantity, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (student_number, medicine_id, quantity)
    VALUES (p_student_number, p_medicine_id, p_quantity);

    RAISE NOTICE 'Dispensed % unit(s) of medicine % to student %.',
                 p_quantity, p_medicine_id, p_student_number;
END $$;

-- ========== STEP 5: Two valid quantities + one exceeding stock ==========
CALL dispense_medicine('2024001', 1, 10);   -- valid
CALL dispense_medicine('2024002', 2, 5);    -- valid
CALL dispense_medicine('2024003', 2, 50);   -- exceeds stock

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- ========== STEP 6: reverse_dispensing procedure (called twice for record 1) ==========
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist.', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed. Stock not restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. % unit(s) restored to stock.', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- restores stock
CALL reverse_dispensing(1);   -- must NOT restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- ========== STEP 7: Explicit cursor with low-stock threshold ==========
DO $$
DECLARE
    v_threshold CONSTANT INT := 20;
    cur_low CURSOR (p_threshold INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_threshold ORDER BY stock_quantity;
    v_name  VARCHAR;
    v_stock INT;
BEGIN
    OPEN cur_low(v_threshold);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % has % in stock', v_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ========== STEP 8: Negative quantity handled with EXCEPTION ==========
DO $$
BEGIN
    CALL dispense_medicine('2024004', 1, -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ========== STEP 9: Final state ==========
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
