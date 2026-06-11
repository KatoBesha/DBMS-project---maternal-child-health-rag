-- =====================================================
-- AGGREGATION QUERIES
-- =====================================================

-- 1. Count documents per topic
SELECT 
    t.topic_name,
    COUNT(dt.doc_id) AS total_documents
FROM topics t
JOIN document_topics dt
    ON t.topic_id = dt.topic_id
GROUP BY t.topic_name;


-- 2. Average retrieval confidence
SELECT 
    AVG(similarity_score) AS average_confidence
FROM query_log;



-- =====================================================
-- JOIN QUERIES
-- =====================================================

-- 3. Show documents with their topics
SELECT 
    d.title,
    t.topic_name
FROM documents d
JOIN document_topics dt
    ON d.doc_id = dt.doc_id
JOIN topics t
    ON dt.topic_id = t.topic_id;


-- 4. Show chunks with their document titles
SELECT 
    d.title,
    c.chunk_text,
    c.token_count
FROM documents d
JOIN chunks c
    ON d.doc_id = c.doc_id;



-- =====================================================
-- SUBQUERY QUERIES
-- =====================================================

-- 5. Documents with above-average similarity scores
SELECT 
    d.title,
    q.similarity_score
FROM query_log q
JOIN documents d
    ON q.cited_doc_id = d.doc_id
WHERE q.similarity_score > (
    SELECT AVG(similarity_score)
    FROM query_log
);


-- 6. Documents that have more chunks than average
SELECT 
    d.title,
    COUNT(c.chunk_id) AS total_chunks
FROM documents d
JOIN chunks c
    ON d.doc_id = c.doc_id
GROUP BY d.doc_id, d.title
HAVING COUNT(c.chunk_id) > (
    SELECT AVG(chunk_count)
    FROM (
        SELECT COUNT(chunk_id) AS chunk_count
        FROM chunks
        GROUP BY doc_id
    ) AS chunk_stats
);



-- =====================================================
-- CTE QUERIES
-- =====================================================

-- 7. Topic retrieval counts using CTE
WITH topic_counts AS (
    SELECT 
        t.topic_name,
        COUNT(*) AS retrieval_count
    FROM query_log q
    JOIN documents d
        ON q.cited_doc_id = d.doc_id
    JOIN document_topics dt
        ON d.doc_id = dt.doc_id
    JOIN topics t
        ON dt.topic_id = t.topic_id
    GROUP BY t.topic_name
)

SELECT *
FROM topic_counts
ORDER BY retrieval_count DESC;


-- 8. Average chunk size per document using CTE
WITH chunk_stats AS (
    SELECT 
        d.doc_id,
        d.title,
        AVG(c.token_count) AS avg_chunk_size
    FROM documents d
    JOIN chunks c
        ON d.doc_id = c.doc_id
    GROUP BY d.doc_id, d.title
)

SELECT *
FROM chunk_stats
ORDER BY avg_chunk_size DESC;



-- =====================================================
-- WINDOW FUNCTION QUERIES
-- =====================================================

-- 9. Rank documents by similarity score
SELECT 
    d.title,
    q.similarity_score,
    RANK() OVER (
        ORDER BY q.similarity_score DESC
    ) AS ranking
FROM query_log q
JOIN documents d
    ON q.cited_doc_id = d.doc_id;


-- 10. Rank chunks within each document by token count
SELECT 
    d.title,
    c.chunk_id,
    c.token_count,
    RANK() OVER (
        PARTITION BY d.doc_id
        ORDER BY c.token_count DESC
    ) AS chunk_rank
FROM documents d
JOIN chunks c
    ON d.doc_id = c.doc_id; 