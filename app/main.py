"""
Maternal & Child Health RAG Application
DBMS Project Z2004 — Final Milestone
"""

import os
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv
from sentence_transformers import SentenceTransformer
import requests

# ── Load environment variables ─────────────────────────────────────────────────
load_dotenv()

DB_CONFIG = {
    "host":     os.getenv("DB_HOST", "localhost"),
    "port":     os.getenv("DB_PORT", "5432"),
    "dbname":   os.getenv("DB_NAME", "dbms"),
    "user":     os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "postgres"),
}

OLLAMA_URL   = "http://localhost:11434/api/generate"
OLLAMA_MODEL = "llama3"

# ── Load embedding model ───────────────────────────────────────────────────────
print("Loading embedding model...")
model = SentenceTransformer("all-MiniLM-L6-v2")
print("Model ready.\n")


# ── Database connection ────────────────────────────────────────────────────────
def get_connection():
    return psycopg2.connect(**DB_CONFIG)


# ── Embed query and search for top-k similar chunks ───────────────────────────
def search_chunks(query: str, top_k: int = 3):
    """
    Embed the user query and find the most similar chunks using
    cosine similarity against stored embeddings in the embeddings table.
    Falls back to keyword search if no embeddings are stored.
    """
    query_embedding = model.encode(query).tolist()

    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute("SELECT COUNT(*) AS cnt FROM embeddings")
    has_embeddings = cur.fetchone()["cnt"] > 0

    if has_embeddings:
        query_vec = "[" + ",".join(str(x) for x in query_embedding) + "]"
        cur.execute("""
            SELECT
                c.chunk_id,
                c.chunk_text,
                c.doc_id,
                d.title,
                d.authors,
                d.source_url,
                d.publication_year,
                1 - (e.embedding_vector <=> %s::vector) AS similarity
            FROM chunks c
            JOIN embeddings e ON c.chunk_id = e.chunk_id
            JOIN documents d ON c.doc_id = d.doc_id
            ORDER BY e.embedding_vector <=> %s::vector
            LIMIT %s
        """, (query_vec, query_vec, top_k))
        results = cur.fetchall()
    else:
        # Fallback: keyword search
        cur.execute("""
            SELECT
                c.chunk_id,
                c.chunk_text,
                c.doc_id,
                d.title,
                d.authors,
                d.source_url,
                d.publication_year,
                0.75 AS similarity
            FROM chunks c
            JOIN documents d ON c.doc_id = d.doc_id
            WHERE d.title ILIKE %s
               OR c.chunk_text ILIKE %s
            ORDER BY d.publication_year DESC
            LIMIT %s
        """, (f"%{query}%", f"%{query}%", top_k))
        results = cur.fetchall()

        if not results:
            cur.execute("""
                SELECT
                    c.chunk_id,
                    c.chunk_text,
                    c.doc_id,
                    d.title,
                    d.authors,
                    d.source_url,
                    d.publication_year,
                    0.60 AS similarity
                FROM chunks c
                JOIN documents d ON c.doc_id = d.doc_id
                ORDER BY d.publication_year DESC, c.chunk_id
                LIMIT %s
            """, (top_k,))
            results = cur.fetchall()

    cur.close()
    conn.close()
    return results


# ── Build a grounded prompt from retrieved chunks ─────────────────────────────
def build_prompt(question: str, chunks: list) -> str:
    context_blocks = []
    for i, chunk in enumerate(chunks, 1):
        context_blocks.append(
            f"[Source {i}] {chunk['title']} ({chunk['publication_year']})\n"
            f"{chunk['chunk_text']}"
        )
    context = "\n\n".join(context_blocks)

    return f"""You are a medical information assistant specialising in maternal and child health.
Answer the question below using ONLY the provided source excerpts.
If the sources do not contain enough information to answer fully, say so clearly.
Be concise, factual, and cite which source(s) support each point using [Source N].

--- SOURCE EXCERPTS ---
{context}
--- END OF SOURCES ---

Question: {question}

Answer:"""


# ── Generate an answer using local Ollama model ───────────────────────────────
def generate_answer(question: str, chunks: list) -> str:
    """Send the retrieved context + question to local Ollama and return its answer."""
    prompt = build_prompt(question, chunks)
    try:
        response = requests.post(
            OLLAMA_URL,
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False
            },
            timeout=120
        )
        response.raise_for_status()
        return response.json()["response"].strip()
    except requests.exceptions.ConnectionError:
        return "[ERROR] Ollama is not running. Please start it with: ollama serve"
    except Exception as e:
        return f"[ERROR] Could not generate answer: {e}"


# ── Log the query to query_log table ──────────────────────────────────────────
def log_query(user_query: str, answer_text: str, cited_doc_id: int, similarity: float):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO query_log (user_query, answer_text, cited_doc_id, similarity_score)
        VALUES (%s, %s, %s, %s)
    """, (user_query, answer_text, cited_doc_id, similarity))
    conn.commit()
    cur.close()
    conn.close()


# ── Format a source citation block ────────────────────────────────────────────
def format_source(result: dict, rank: int) -> str:
    return (
        f"\n  [{rank}] {result['title']} ({result['publication_year']})"
        f"\n      Authors : {result['authors'][:80]}{'...' if len(result['authors']) > 80 else ''}"
        f"\n      Source  : {result['source_url']}"
        f"\n      Score   : {float(result['similarity']):.4f}"
    )


# ── Main RAG query function ────────────────────────────────────────────────────
def ask(question: str):
    print(f"\n{'═' * 60}")
    print(f"  Question: {question}")
    print(f"{'═' * 60}")

    results = search_chunks(question, top_k=3)

    if not results:
        print("\n  No relevant documents found.")
        return

    # ── Generate a real answer locally ────────────────────────────────────
    print("\n  Generating answer from retrieved context...\n")
    answer = generate_answer(question, results)

    print("  ANSWER")
    print("  " + "─" * 58)
    for line in answer.splitlines():
        print(f"  {line}")

    # ── Print source citations ─────────────────────────────────────────────
    print(f"\n  SOURCES USED")
    print("  " + "─" * 58)
    for i, r in enumerate(results, 1):
        print(format_source(r, i))

    # Log the top result
    top = results[0]
    log_query(question, answer, top["doc_id"], float(top["similarity"]))
    print(f"\n  [Query logged to database]")


# ── DB health check ────────────────────────────────────────────────────────────
def check_db():
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM documents")
        doc_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM chunks")
        chunk_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM embeddings")
        embed_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM query_log")
        log_count = cur.fetchone()[0]
        cur.close()
        conn.close()
        print(f"  Database connected successfully.")
        print(f"  Documents  : {doc_count}")
        print(f"  Chunks     : {chunk_count}")
        print(f"  Embeddings : {embed_count}")
        print(f"  Query Log  : {log_count} entries")
        return True
    except Exception as e:
        print(f"  [ERROR] Could not connect to database: {e}")
        return False


# ── Ollama health check ────────────────────────────────────────────────────────
def check_ollama():
    try:
        response = requests.get("http://localhost:11434", timeout=5)
        print(f"  Ollama running  : yes (model: {OLLAMA_MODEL})")
        return True
    except Exception:
        print(f"  [WARNING] Ollama not detected. Start it with: ollama serve")
        print(f"            Then pull the model with:          ollama pull {OLLAMA_MODEL}")
        return False


# ── Entry point ────────────────────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("  Maternal & Child Health RAG System")
    print("  DBMS Project Z2004")
    print("=" * 60)

    print("\nChecking database connection...")
    if not check_db():
        print("\nCannot connect to DB. Check your .env file.")
        return

    print("\nChecking Ollama...")
    check_ollama()

    # ── 3 required test cases ──────────────────────────────────────────────
    test_questions = [
        "What are the risks of preterm birth?",
        "How does maternal nutrition affect infant development?",
        "What vaccines are recommended during pregnancy?",
    ]

    print("\n\nRunning 3 test cases...\n")
    for q in test_questions:
        ask(q)

    # ── Interactive mode ───────────────────────────────────────────────────
    print(f"\n\n{'═' * 60}")
    print("  Interactive Mode — type your question or 'quit' to exit")
    print(f"{'═' * 60}")

    while True:
        try:
            user_input = input("\n  Your question: ").strip()
            if user_input.lower() in ("quit", "exit", "q"):
                print("\n  Goodbye!\n")
                break
            if not user_input:
                continue
            ask(user_input)
        except KeyboardInterrupt:
            print("\n\n  Interrupted. Goodbye!\n")
            break


if __name__ == "__main__":
    main()
