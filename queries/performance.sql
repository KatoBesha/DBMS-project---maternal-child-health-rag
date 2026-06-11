INSERT INTO topics(topic_name, description)
VALUES
('Preconception','Before pregnancy'),
('Prenatal','During pregnancy'),
('Birth','Delivery'),
('Newborn','0-1 month'),
('Infant','1-12 months'),
('Toddler','1-3 years'),
('Nutrition','Diet guidance'),
('Vaccination','Immunisation'),
('Maternal Health','Mother wellbeing'),
('Child Development','Growth milestones');


INSERT INTO documents
(
    title,
    authors,
    source_url,
    publication_year,
    stage
)
SELECT
    'Document ' || gs,
    'Author ' || gs,
    'https://source' || gs || '.com',
    2020 + (random()*5)::int,
    (
        ARRAY[
            'Preconception',
            'Prenatal',
            'Birth',
            'Newborn',
            'Infant',
            'Toddler'
        ]
    )[floor(random()*6+1)]
FROM generate_series(1,5000) gs;


INSERT INTO chunks
(
    doc_id,
    chunk_index,
    chunk_text,
    token_count
)
SELECT
    d.doc_id,
    gs,
    'Chunk text ' || gs,
    100 + floor(random()*200)::int
FROM documents d
CROSS JOIN generate_series(1,10) gs;


INSERT INTO document_topics
(
    doc_id,
    topic_id
)
SELECT
    d.doc_id,
    floor(random()*10+1)::int
FROM documents d;


INSERT INTO query_log
(
    user_query,
    answer_text,
    cited_doc_id,
    similarity_score
)
SELECT
    'Question ' || gs,
    'Answer ' || gs,
    (
        SELECT doc_id
        FROM documents
        ORDER BY random()
        LIMIT 1
    ),
    random()
FROM generate_series(1,20000) gs;

SELECT COUNT(*) FROM documents;
SELECT COUNT(*) FROM chunks;
SELECT COUNT(*) FROM query_log;


DROP INDEX idx_documents_stage;

EXPLAIN ANALYZE
SELECT *
FROM documents
WHERE stage = 'Prenatal';

CREATE INDEX idx_documents_stage
ON documents(stage);

EXPLAIN ANALYZE
SELECT *
FROM documents
WHERE stage = 'Prenatal';



DROP INDEX Idx_chunks_doc_id;

EXPLAIN ANALYZE
SELECT *
FROM chunks
WHERE doc_id =
(
    SELECT doc_id
    FROM documents
    LIMIT 1
);

CREATE INDEX idx_chunks_doc_id
    ON chunks (doc_id);



DROP INDEX Idx_query_log_cited_doc;

EXPLAIN ANALYZE
SELECT *
FROM query_log
WHERE cited_doc_id =
(
    SELECT doc_id
    FROM documents
    LIMIT 1
);


CREATE INDEX idx_query_log_cited_doc
    ON query_log (cited_doc_id);


CREATE OR REPLACE PROCEDURE get_documents_by_stage(
    p_stage VARCHAR
)
LANGUAGE SQL
AS $$
SELECT *
FROM documents
WHERE stage = p_stage;
$$;

CALL get_documents_by_stage('Prenatal');	



CREATE TABLE activity_log (
    log_id SERIAL PRIMARY KEY,
    action_text TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION log_query_insert()
RETURNS TRIGGER
AS $$
BEGIN

    INSERT INTO activity_log(action_text)
    VALUES ('New query added to query_log');

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_query_insert
AFTER INSERT ON query_log
FOR EACH ROW
EXECUTE FUNCTION log_query_insert();

INSERT INTO query_log
(
    user_query,
    answer_text,
    cited_doc_id,
    similarity_score
)
VALUES
(
    'Test question',
    'Test answer',
    (SELECT doc_id FROM documents LIMIT 1),
    0.95
);

SELECT *
FROM activity_log;
