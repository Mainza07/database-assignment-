-- ICT371 Scenario 1: University Library Book Loans
-- Run each numbered step separately (highlight + F5) so every screenshot is clear.
-- Notices (RAISE NOTICE) appear in the "Messages" tab.

-- ========== STEP 1: Tables and data ==========
DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    book_id        INT NOT NULL REFERENCES books(book_id),
    quantity       INT NOT NULL,
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
);

INSERT INTO books (title, available_copies) VALUES
    ('Database System Concepts', 5),
    ('Operating System Concepts', 1),
    ('Computer Networks', 0),
    ('Software Engineering', 8);

SELECT * FROM books ORDER BY book_id;

-- ========== STEP 2: IF / ELSIF / ELSE ==========
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '% : LOW ON COPIES (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- ========== STEP 3: WHILE and numeric FOR ==========
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', counter;
        counter := counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', i;
    END LOOP;
END $$;

-- ========== STEP 4: borrow_book procedure ==========
CREATE OR REPLACE PROCEDURE borrow_book(
    p_student_number VARCHAR,
    p_book_id        INT,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist.', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available.',
                     p_student_number, p_quantity, v_available;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (student_number, book_id, quantity)
    VALUES (p_student_number, p_book_id, p_quantity);

    RAISE NOTICE 'Loan recorded for student %: % copy/copies of book %.',
                 p_student_number, p_quantity, p_book_id;
END $$;

-- ========== STEP 5: Two valid loans + one exceeding stock ==========
CALL borrow_book('2024001', 1, 2);    -- valid
CALL borrow_book('2024002', 2, 1);    -- valid
CALL borrow_book('2024003', 1, 10);   -- exceeds available copies

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ========== STEP 6: return_book procedure (called twice for loan 1) ==========
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist.', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored.', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- restores copies
CALL return_book(1);   -- must NOT restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ========== STEP 7: Explicit cursor (books with few copies) ==========
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 2 ORDER BY available_copies;
    v_title  VARCHAR;
    v_copies INT;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies remaining: % (% left)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- ========== STEP 8: Zero copies handled with EXCEPTION ==========
DO $$
BEGIN
    CALL borrow_book('2024004', 1, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ========== STEP 9: Final state ==========
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
