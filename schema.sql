-- ============================================================
-- Z2004: Database Management Systems — Semester Project
-- RAG Pipeline: Pre-conception to Early Childhood
-- IIT Madras Zanzibar | Even Semester 2026
-- ============================================================
-- Schema follows 3NF throughout.
-- Functional dependencies and design justifications are
-- documented inline for each table.
-- ============================================================

-- Enable pgvector extension for storing embedding vectors
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- TABLE: topics
-- Controlled vocabulary for life-stage classification.
-- 
-- Functional Dependencies:
--   topic_id -> topic_name
--   topic_id -> description
-- 
-- 3NF: Single-column PK; all attributes depend only on
-- topic_id. No transitive dependencies possible.
-- ============================================================
CREATE TABLE topics (
    topic_id    SERIAL          PRIMARY KEY,
    topic_name  VARCHAR(100)    NOT NULL UNIQUE,  -- e.g. 'Preconception', 'Prenatal', 'Newborn', 'Toddler'
    description TEXT,

    CONSTRAINT chk_topic_name_not_empty CHECK (TRIM(topic_name) <> '')
);


-- ============================================================
-- TABLE: documents
-- Stores one row per source document (paper, guideline, etc.).
-- This is the anchor table for the entire RAG system.
--
-- Functional Dependencies:
--   doc_id -> title
--   doc_id -> authors
--   doc_id -> source_url
--   doc_id -> publication_year
--   doc_id -> stage
--   doc_id -> created_at
--
-- 3NF: All non-key attributes depend solely on doc_id.
-- No attribute depends on another non-key attribute.
-- stage is a denormalised convenience field (e.g. 'prenatal');
-- fine-grained topic tagging is handled via document_topics.
-- ============================================================
CREATE TABLE documents (
    doc_id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    title               VARCHAR(500)    NOT NULL,
    authors             TEXT,                       -- free-text author list
    source_url          TEXT            UNIQUE,     -- original URL or DOI
    publication_year    SMALLINT,                   -- e.g. 2023
    stage               VARCHAR(50),                -- broad life stage label
    created_at          TIMESTAMP       NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_publication_year CHECK (
        publication_year IS NULL OR
        (publication_year >= 1900 AND publication_year <= EXTRACT(YEAR FROM NOW()))
    )
);


-- ============================================================
-- TABLE: document_topics
-- Junction table resolving the M:N relationship between
-- documents and topics.
-- One document can cover many topics; one topic can appear
-- in many documents.
--
-- Functional Dependencies:
--   (doc_id, topic_id) -> (no other non-key attributes)
--
-- 3NF: Composite PK only. No non-key attributes exist,
-- so transitive dependency violations are impossible.
-- ============================================================
CREATE TABLE document_topics (
    doc_id      UUID    NOT NULL REFERENCES documents(doc_id) ON DELETE CASCADE,
    topic_id    INT     NOT NULL REFERENCES topics(topic_id)  ON DELETE CASCADE,

    PRIMARY KEY (doc_id, topic_id)  -- composite PK enforces uniqueness
);


-- ============================================================
-- TABLE: chunks
-- Each document is split into smaller text segments for
-- embedding. Keeps chunk text separate from document metadata
-- to avoid partial-key dependency violations.
--
-- Functional Dependencies:
--   chunk_id -> doc_id
--   chunk_id -> chunk_index
--   chunk_id -> chunk_text
--   chunk_id -> token_count
--
-- 3NF: All attributes depend on chunk_id alone.
-- chunk_index and chunk_text do NOT depend on each other,
-- satisfying 3NF.
-- ============================================================
CREATE TABLE chunks (
    chunk_id        UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_id          UUID    NOT NULL REFERENCES documents(doc_id) ON DELETE CASCADE,
    chunk_index     INT     NOT NULL,               -- ordering within the document
    chunk_text      TEXT    NOT NULL,               -- the actual text segment
    token_count     INT     NOT NULL,               -- number of tokens in chunk

    CONSTRAINT chk_token_count   CHECK (token_count > 0),
    CONSTRAINT chk_chunk_index   CHECK (chunk_index >= 0),
    CONSTRAINT uq_chunk_order    UNIQUE (doc_id, chunk_index)  -- no duplicate positions
);


-- ============================================================
-- TABLE: embeddings
-- Stores the vector representation of each chunk.
-- Kept separate from chunks because embedding metadata
-- (model_name, created_at) describes the *embedding process*,
-- not the chunk text itself — separating them prevents a
-- transitive dependency and is the core 3NF design decision.
--
-- Functional Dependencies:
--   embedding_id -> chunk_id
--   embedding_id -> embedding_vector
--   embedding_id -> model_name
--   embedding_id -> created_at
--
-- 3NF: model_name and created_at depend on embedding_id,
-- NOT on chunk_id or chunk_text. No transitive dependencies.
-- ============================================================
CREATE TABLE embeddings (
    embedding_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    chunk_id            UUID        NOT NULL UNIQUE REFERENCES chunks(chunk_id) ON DELETE CASCADE,
    embedding_vector    vector(384) NOT NULL,        -- 384-dim for sentence-transformers default
    model_name          VARCHAR(200) NOT NULL,       -- e.g. 'all-MiniLM-L6-v2'
    created_at          TIMESTAMP   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_model_name_not_empty CHECK (TRIM(model_name) <> '')
);

-- Index for fast cosine similarity search (pgvector)
-- This is the primary index enabling RAG retrieval.
CREATE INDEX idx_embeddings_vector
    ON embeddings
    USING ivfflat (embedding_vector vector_cosine_ops)
    WITH (lists = 100);


-- ============================================================
-- TABLE: query_log
-- Records every user query, the answer returned, which
-- document was cited, and the similarity score.
-- Essential for M3 performance analysis and future
-- recommendation improvements.
--
-- Functional Dependencies:
--   query_id -> user_query
--   query_id -> answer_text
--   query_id -> cited_doc_id
--   query_id -> similarity_score
--   query_id -> queried_at
--
-- 3NF: All attributes depend only on query_id.
-- cited_doc_id is a FK reference, not a transitive dependency —
-- no document attributes are stored here.
-- ============================================================
CREATE TABLE query_log (
    query_id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_query          TEXT        NOT NULL,        -- the natural-language question
    answer_text         TEXT,                        -- the generated answer
    cited_doc_id        UUID        REFERENCES documents(doc_id) ON DELETE SET NULL,
    similarity_score    FLOAT,                       -- cosine similarity of top retrieved chunk
    queried_at          TIMESTAMP   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_similarity_range CHECK (
        similarity_score IS NULL OR
        (similarity_score >= 0.0 AND similarity_score <= 1.0)
    )
);

-- Index to support performance queries by time (useful in M3)
CREATE INDEX idx_query_log_queried_at
    ON query_log (queried_at DESC);

-- Index to find all queries that cited a specific document
CREATE INDEX idx_query_log_cited_doc
    ON query_log (cited_doc_id);

-- B-Tree index on documents.stage for filtered RAG retrieval
-- (e.g. "only search prenatal documents")
-- Required by Track A: at least one B-Tree index with EXPLAIN ANALYZE evidence
CREATE INDEX idx_documents_stage
    ON documents (stage);

-- B-Tree index on chunks.doc_id for fast chunk lookup by document
CREATE INDEX idx_chunks_doc_id
    ON chunks (doc_id);
