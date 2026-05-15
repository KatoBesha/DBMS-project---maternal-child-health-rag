# Early Life RAG — Maternal & Child Health Question Answering System
**Z2004: Database Management Systems | IIT Madras Zanzibar | Even Semester 2026**
**Track A: RAG Pipeline (Retrieval-Augmented Generation)**
**Team:** Milliam Rukanda, Mwewa Ruby Mumba, Emmanuel Siyauya
**Milestone 2 Submission**
**GitHub:** [https://github.com/KatoBesha/DBMS-project---maternal-child-health-rag](https://github.com/KatoBesha/DBMS-project---maternal-child-health-rag)

---

## Project Description

This project is a Retrieval-Augmented Generation (RAG) system that answers natural language questions about maternal and child health — covering preconception, pregnancy, newborn care, and toddler development. The system is backed by a normalised PostgreSQL relational database containing real research papers and clinical guidelines sourced from PubMed, Europe PMC, and Semantic Scholar.

Given a user question, the system retrieves the most semantically relevant document chunks and returns a grounded answer with source citations.

---

## Repository Structure

```
early-life-rag/
├── /schema/
│   ├── schema.sql          — DDL script to create all tables and indexes
│   └── er_diagram.png      — Entity-Relationship diagram
├── /data/
│   ├── topics.csv
│   ├── documents.csv
│   ├── document_topics.csv
│   ├── chunks.csv
│   └── query_log.csv
├── /queries/
│   └── queries.sql         — All 10 M2 queries
├── /app/                   — Python RAG application (Final submission)
├── /report/                — Written report (Final submission)
├── /demo/                  — Demo video (Final submission)
└── README.md
```

---

## Data Sources

| Source | Description | URL |
|--------|-------------|-----|
| PubMed | Biomedical research abstracts via Entrez API | pubmed.ncbi.nlm.nih.gov |
| Europe PMC | International biomedical literature | europepmc.org |
| Semantic Scholar | Academic paper metadata and abstracts | semanticscholar.org |

**Search terms used:**
- preconception health, fertility, conception
- prenatal care, antenatal care, pregnancy, maternal nutrition
- newborn care, neonatal, infant, breastfeeding, postpartum
- toddler development, child development, developmental milestones, early childhood

**Data collection steps:**
1. Queried each source API with domain-specific search terms
2. Extracted title, authors, source URL, publication year, and abstract
3. Removed duplicates on source_url
4. Removed rows with empty abstracts
5. Exported to documents.csv

**AI Usage Disclosure:**
Claude (Anthropic) was used to assist with SQL query structure suggestions, debugging, and README drafting. All queries were reviewed, tested, and adapted by the team. All data was sourced from real academic databases — no AI-generated content was used as data.

---

## Data Dictionary

### topics
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| topic_id | SERIAL | Unique identifier for each topic | Primary Key |
| topic_name | VARCHAR(100) | Name of the life stage topic (e.g. Prenatal) | Unique, Not Null |
| description | TEXT | Brief description of what the topic covers | Optional |

### documents
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| doc_id | UUID | Unique identifier for each document | Primary Key |
| title | VARCHAR(500) | Title of the research paper or guideline | Not Null |
| authors | TEXT | Comma-separated list of author names | Optional |
| source_url | TEXT | URL or DOI linking to the original source | Unique |
| publication_year | SMALLINT | Year the paper was published (1900–2026) | Optional |
| stage | VARCHAR(50) | Broad life stage label (set to 'mixed') | Optional |
| created_at | TIMESTAMP | When the record was inserted | Not Null, Default NOW() |

### document_topics
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| doc_id | UUID | References the document | Foreign Key → documents |
| topic_id | INT | References the topic | Foreign Key → topics |

*Junction table resolving the many-to-many relationship between documents and topics. One document can cover multiple topics.*

### chunks
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| chunk_id | UUID | Unique identifier for each chunk | Primary Key |
| doc_id | UUID | The document this chunk belongs to | Foreign Key → documents |
| chunk_index | INT | Position of the chunk within the document (0-based) | Not Null, ≥ 0 |
| chunk_text | TEXT | The actual text content of the chunk | Not Null |
| token_count | INT | Number of characters in the chunk | Not Null, > 0 |

*Each document abstract is split into multiple chunks of ~500 characters for embedding and retrieval.*

### embeddings
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| embedding_id | UUID | Unique identifier for each embedding | Primary Key |
| chunk_id | UUID | The chunk this embedding represents | Foreign Key → chunks, Unique |
| embedding_vector | vector(384) | 384-dimensional vector from sentence-transformers | Not Null |
| model_name | VARCHAR(200) | Name of the embedding model used | Not Null |
| created_at | TIMESTAMP | When the embedding was generated | Not Null |

*Note: embeddings table will be populated in the final submission using the sentence-transformers Python library.*

### query_log
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| query_id | UUID | Unique identifier for each query | Primary Key |
| user_query | TEXT | The natural language question asked by the user | Not Null |
| answer_text | TEXT | The generated answer returned by the RAG system | Optional |
| cited_doc_id | UUID | The document cited as the source of the answer | Foreign Key → documents |
| similarity_score | FLOAT | Cosine similarity score of the retrieved chunk (0.0–1.0) | Optional |
| queried_at | TIMESTAMP | When the query was made | Not Null, Default NOW() |

---

## Dataset Summary

| Table | Row Count | Notes |
|-------|-----------|-------|
| topics | 4 | Preconception, Prenatal, Newborn, Toddler |
| documents | 2,702 | Real research papers and clinical guidelines |
| document_topics | 4,543 | Many documents tagged with multiple topics |
| chunks | 10,896 | ~4 chunks per document on average |
| query_log | 10 | Sample queries for M2; real queries added in final submission |
| **Total** | **19,155** | |

---

## Environment Setup

### Requirements

- PostgreSQL 16
- Python 3.10+
- pgvector extension

### Install Python dependencies

```bash
pip install psycopg2-binary python-dotenv pandas biopython sentence-transformers
```

### Environment variables

Create a `.env` file in the project root (never commit this):

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=your_database_name
DB_USER=postgres
DB_PASSWORD=your_password
```

---

## Step-by-Step Reproduction Instructions

Follow these steps exactly to reproduce the database from scratch on a clean machine.

### Step 1: Create the database

Open PgAdmin, create a new database called `dbms`, then open the Query Tool and run:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

### Step 2: Create all tables

In PgAdmin Query Tool, open and run `/schema/schema.sql`. This creates all 6 tables with constraints and indexes.

Verify:
```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
```
You should see: topics, documents, document_topics, chunks, embeddings, query_log.

### Step 3: Create staging table and import documents

Run in Query Tool:
```sql
CREATE TABLE documents_staging (
    title            TEXT,
    authors          TEXT,
    source_url       TEXT,
    publication_year TEXT,
    abstract         TEXT
);
```

Then in PgAdmin:
1. Right click `documents_staging` → Import/Export Data
2. Toggle: **Import**
3. File: select `data/documents.csv`
4. Format: CSV | Header: ON | Delimiter: `,` | Encoding: UTF8
5. Click OK

### Step 4: Insert topics

```sql
INSERT INTO topics (topic_name, description) VALUES
('Preconception', 'Content related to fertility and preconception health'),
('Prenatal',      'Content related to pregnancy and prenatal care'),
('Newborn',       'Content related to newborn and infant care'),
('Toddler',       'Content related to toddler development milestones');
```

### Step 5: Populate documents table

```sql
INSERT INTO documents (doc_id, title, authors, source_url, publication_year, stage)
SELECT
    gen_random_uuid(),
    LEFT(title, 500),
    LEFT(authors, 500),
    LEFT(source_url, 450),
    CASE
        WHEN publication_year ~ '^\d{4}$'
        THEN publication_year::SMALLINT
        ELSE NULL
    END,
    'mixed'
FROM documents_staging
WHERE title IS NOT NULL
  AND abstract IS NOT NULL
  AND TRIM(abstract) != ''
ON CONFLICT (source_url) DO NOTHING;
```

### Step 6: Populate document_topics

```sql
INSERT INTO document_topics (doc_id, topic_id)
SELECT DISTINCT d.doc_id, t.topic_id
FROM documents d
JOIN documents_staging ds ON LEFT(ds.source_url, 450) = d.source_url
CROSS JOIN topics t
WHERE
    (t.topic_name = 'Preconception' AND (
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%preconception%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%fertility%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%conception%'
    ))
    OR
    (t.topic_name = 'Prenatal' AND (
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%prenatal%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%pregnancy%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%maternal%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%antenatal%'
    ))
    OR
    (t.topic_name = 'Newborn' AND (
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%newborn%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%neonatal%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%infant%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%breastfeeding%'
    ))
    OR
    (t.topic_name = 'Toddler' AND (
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%toddler%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%child development%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%milestone%' OR
        LOWER(ds.title || ' ' || ds.abstract) LIKE '%early childhood%'
    ))
ON CONFLICT DO NOTHING;
```

### Step 7: Populate chunks

```sql
INSERT INTO chunks (chunk_id, doc_id, chunk_index, chunk_text, token_count)
SELECT
    gen_random_uuid(),
    d.doc_id,
    chunk_num,
    SUBSTRING(ds.abstract, (chunk_num * 500) + 1, 500),
    LENGTH(SUBSTRING(ds.abstract, (chunk_num * 500) + 1, 500))
FROM documents d
JOIN documents_staging ds
    ON LEFT(ds.source_url, 450) = d.source_url,
LATERAL generate_series(0,
    LEAST(FLOOR(LENGTH(ds.abstract) / 500)::int, 4)
) AS chunk_num
WHERE LENGTH(ds.abstract) > 0
  AND LENGTH(SUBSTRING(ds.abstract, (chunk_num * 500) + 1, 500)) > 0
ON CONFLICT DO NOTHING;
```

### Step 8: Populate query_log

```sql
INSERT INTO query_log (query_id, user_query, answer_text, cited_doc_id, similarity_score, queried_at)
SELECT
    gen_random_uuid(),
    user_query,
    answer_text,
    (SELECT doc_id FROM documents ORDER BY RANDOM() LIMIT 1),
    ROUND((RANDOM() * 0.4 + 0.6)::numeric, 2),
    NOW() - (RANDOM() * INTERVAL '30 days')
FROM (VALUES
    ('What are the signs of preterm labor?',       'Signs include regular contractions before 37 weeks...'),
    ('How much folic acid during pregnancy?',       'WHO recommends 400mcg of folic acid daily...'),
    ('When do toddlers start walking?',             'Most toddlers take their first steps between 9-12 months...'),
    ('What vaccinations does a newborn need?',      'Newborns receive Hepatitis B vaccine at birth...'),
    ('How to manage morning sickness?',             'Eating small frequent meals and staying hydrated helps...'),
    ('What is preeclampsia?',                       'Preeclampsia is high blood pressure during pregnancy...'),
    ('When should I start prenatal care?',          'Prenatal care should begin in the first trimester...'),
    ('What foods to avoid during pregnancy?',       'Avoid raw fish, unpasteurized dairy, and high mercury fish...'),
    ('How often should a newborn feed?',            'Newborns typically feed every 2-3 hours...'),
    ('What are developmental milestones at age 2?', 'At age 2 children should have about 50 words...')
) AS q(user_query, answer_text);
```

### Step 9: Run queries

Open `/queries/queries.sql` in PgAdmin Query Tool and run each query. All 10 queries should return meaningful results.

### Step 10: Verify final counts

```sql
SELECT
    (SELECT COUNT(*) FROM topics)          AS topics,
    (SELECT COUNT(*) FROM documents)       AS documents,
    (SELECT COUNT(*) FROM document_topics) AS document_topics,
    (SELECT COUNT(*) FROM chunks)          AS chunks,
    (SELECT COUNT(*) FROM query_log)       AS query_log;
```

Expected output: 4 | 2702 | 4543 | 10896 | 10

---

## Queries Overview

All queries are in `/queries/queries.sql`. Each is labelled and commented.

| # | Type | Description |
|---|------|-------------|
| 1 | Aggregation | Count documents per topic |
| 2 | Aggregation | Average retrieval confidence score |
| 3 | Join | Documents with their assigned topics |
| 4 | Join | Chunks with their parent document titles |
| 5 | Subquery | Documents cited above average similarity score |
| 6 | Subquery | Documents with more chunks than average |
| 7 | CTE | Topic retrieval counts |
| 8 | CTE | Average chunk size per document |
| 9 | Window Function | Rank documents by similarity score |
| 10 | Window Function | Rank chunks within each document by size |
