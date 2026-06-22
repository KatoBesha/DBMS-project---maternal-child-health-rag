# Early Life RAG — Maternal & Child Health Question Answering System
**Z2004: Database Management Systems | IIT Madras Zanzibar | Even Semester 2026**  
**Track A: RAG Pipeline (Retrieval-Augmented Generation)**  
**Team:** Milliam Rukanda, Mwewa Ruby Mumba, Emmanuel Siyauya  
**Final Milestone Submission**  
**GitHub:** [https://github.com/KatoBesha/DBMS-project---maternal-child-health-rag](https://github.com/KatoBesha/DBMS-project---maternal-child-health-rag)

---

## Project Description

This project is a Retrieval-Augmented Generation (RAG) system that answers natural language questions about maternal and child health — covering preconception, pregnancy, newborn care, and toddler development. The system is backed by a normalised PostgreSQL relational database containing real research papers and clinical guidelines sourced from PubMed, Europe PMC, and Semantic Scholar.

Given a user question, the system:
1. Embeds the question using `sentence-transformers`
2. Retrieves the most semantically similar document chunks from PostgreSQL using `pgvector` cosine similarity
3. Passes the retrieved context to a locally running `llama3` model via Ollama
4. Returns a grounded answer with source citations

---
## Demo Video
▶️ Watch the full demo here: https://drive.google.com/file/d/1gEvENCmx6Ey6hb9ezKIy94J5C9I66XEp/view?usp=sharing

## Repository Structure

```
early-life-rag/
├── /schema/
│   ├── schema.sql              — DDL script to create all tables and indexes
│   └── er_diagram.png          — Entity-Relationship diagram
├── /data/
│   └── documents.csv           — 2,702 research papers (source data)
├── /queries/
│   ├── queries.sql             — All 10 M2 queries
│   └── performance.sql         — M3 index + stored procedure + trigger SQL
├── /app/
│   └── main.py                 — Python RAG application
├── /report/
│   └── Z2004_Written_Report.pdf — Final written report
├── /demo/                      — Demo video (final submission)
├── database_dump.sql           — Full PostgreSQL database dump (restore to run app)
├── .env.example                — Environment variable template
├── requirements.txt            — Python dependencies
└── README.md
```

---

## Quick Start (Running the App)

> **This is the fastest way to get the app running.** Use the database dump — no manual setup needed.

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| PostgreSQL | 16+ | [postgresql.org](https://www.postgresql.org/download/) |
| Python | 3.10+ | [python.org](https://www.python.org/downloads/) |
| Ollama | latest | [ollama.com](https://ollama.com/download) |

---

### Step 1: Clone the repository

```bash
git clone https://github.com/KatoBesha/DBMS-project---maternal-child-health-rag.git
cd DBMS-project---maternal-child-health-rag
```

---

### Step 2: Restore the database from dump

Open **pgAdmin** or **psql** and create a new empty database called `dbms`, then enable pgvector:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

Then restore the dump from the terminal:

```bash
psql -U postgres -d dbms < database_dump.sql
```

Verify it worked:

```sql
SELECT
    (SELECT COUNT(*) FROM topics)          AS topics,
    (SELECT COUNT(*) FROM documents)       AS documents,
    (SELECT COUNT(*) FROM chunks)          AS chunks,
    (SELECT COUNT(*) FROM embeddings)      AS embeddings,
    (SELECT COUNT(*) FROM query_log)       AS query_log;
```

Expected: `4 | 2702 | ~10896 | ~10896 | 10+`

---

### Step 3: Set up environment variables

Copy the example file and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env`:

```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=dbms
DB_USER=postgres
DB_PASSWORD=your_password
```

---

### Step 4: Install Python dependencies

```bash
pip install -r requirements.txt
```

---

### Step 5: Start Ollama and pull the model

```bash
# Start Ollama (keep this running in a separate terminal)
ollama serve

# Pull the llama3 model (first time only — ~4GB download)
ollama pull llama3
```

---

### Step 6: Run the application

```bash
python app/main.py
```

The app will:
- Check the database connection and print row counts
- Check that Ollama is running
- Automatically run 3 test questions and print answers with source citations
- Enter interactive mode where you can type your own questions

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

---

## Data Dictionary

### topics
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| topic_id | SERIAL | Unique identifier for each topic | Primary Key |
| topic_name | VARCHAR(100) | Name of the life stage topic | Unique, Not Null |
| description | TEXT | Brief description of the topic | Optional |

### documents
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| doc_id | UUID | Unique identifier for each document | Primary Key |
| title | VARCHAR(500) | Title of the research paper | Not Null |
| authors | TEXT | Comma-separated list of authors | Optional |
| source_url | TEXT | URL or DOI to the original source | Unique |
| publication_year | SMALLINT | Year published (1900–2026) | Optional |
| stage | VARCHAR(50) | Life stage label | Optional |
| created_at | TIMESTAMP | Insertion timestamp | Not Null, Default NOW() |

### document_topics
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| doc_id | UUID | References the document | Foreign Key → documents |
| topic_id | INT | References the topic | Foreign Key → topics |

### chunks
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| chunk_id | UUID | Unique identifier for each chunk | Primary Key |
| doc_id | UUID | Parent document | Foreign Key → documents |
| chunk_index | INT | Position within the document (0-based) | Not Null, ≥ 0 |
| chunk_text | TEXT | Text content of the chunk | Not Null |
| token_count | INT | Character count of the chunk | Not Null, > 0 |

### embeddings
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| embedding_id | UUID | Unique identifier | Primary Key |
| chunk_id | UUID | The chunk this embedding represents | Foreign Key → chunks, Unique |
| embedding_vector | vector(384) | 384-dimensional sentence-transformer vector | Not Null |
| model_name | VARCHAR(200) | Embedding model used | Not Null |
| created_at | TIMESTAMP | Generation timestamp | Not Null |

### query_log
| Column | Type | Description | Constraints |
|--------|------|-------------|-------------|
| query_id | UUID | Unique identifier | Primary Key |
| user_query | TEXT | Natural language question | Not Null |
| answer_text | TEXT | Generated answer | Optional |
| cited_doc_id | UUID | Primary cited document | Foreign Key → documents |
| similarity_score | FLOAT | Cosine similarity score (0.0–1.0) | Optional |
| queried_at | TIMESTAMP | When the query was made | Not Null, Default NOW() |

---

## Dataset Summary

| Table | Row Count | Notes |
|-------|-----------|-------|
| topics | 4 | Preconception, Prenatal, Newborn, Toddler |
| documents | 2,702 | Real research papers and clinical guidelines |
| document_topics | 4,543 | Many documents tagged with multiple topics |
| chunks | ~10,896 | ~4 chunks per document on average |
| embeddings | ~10,896 | One 384-dim vector per chunk |
| query_log | 10+ | Grows with each interactive session |
| **Total** | **~29,000+** | |

---

## Queries Overview

All queries are in `/queries/queries.sql`.

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

Milestone 3 performance queries, index DDL, stored procedure, and trigger are all in `/queries/performance.sql`.

---

## Milestone 3 — Performance Summary

Three queries were profiled using `EXPLAIN ANALYZE` before and after B-Tree indexing:

| Query | Table | Before (ms) | After (ms) | Improvement |
|-------|-------|-------------|------------|-------------|
| `WHERE stage = 'Prenatal'` | documents | 0.339 | 0.209 | 38% |
| `WHERE doc_id = (subquery)` | chunks | 0.162 | 0.089 | 45% |
| `WHERE cited_doc_id = (subquery)` | query_log | 1.061 | 1.025 | 3% (expected — zero-result query) |

A stored procedure (`get_documents_by_stage`) and an audit trigger (`trg_query_insert`) were implemented. See `/queries/performance.sql` and the Milestone 3 report in `/report/`.

---

## Troubleshooting

**`Could not connect to database`** — Check your `.env` file credentials and ensure PostgreSQL is running.

**`Ollama is not running`** — Run `ollama serve` in a separate terminal before starting the app.

**`llama3 model not found`** — Run `ollama pull llama3` (requires ~4GB download, one time only).

**`vector type not found`** — Run `CREATE EXTENSION IF NOT EXISTS vector;` in your `dbms` database.

**`psql: command not found`** — Add PostgreSQL's `bin` folder to your system PATH, or use pgAdmin's Restore tool instead of the command line.

---

## AI Usage Disclosure

Claude (Anthropic) was used to assist with SQL query structure suggestions, debugging, README drafting, and LaTeX report writing. All queries were reviewed, tested, and adapted by the team. All data was sourced from real academic databases — no AI-generated content was used as data.