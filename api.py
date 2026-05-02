"""
Pipeline API — FastAPI bridge between n8n (Docker) and the local vault scripts.
Runs on the Windows host at port 8001.
n8n calls http://host.docker.internal:8001/<command> on a schedule.
"""

import os
import platform
import subprocess
import sqlite3
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

load_dotenv()

VAULT_ROOT = Path(os.environ.get("VAULT_ROOT", "~/SecondBrain")).expanduser()
CNS = VAULT_ROOT / "scripts" / "cns.sh"


def _find_bash() -> str:
    """Locate Git Bash on Windows; fall back to system bash on Linux/Mac."""
    if platform.system() != "Windows":
        return "bash"
    candidates = [
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files (x86)\Git\bin\bash.exe",
        os.path.expandvars(r"%LOCALAPPDATA%\Programs\Git\bin\bash.exe"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return "bash"  # last resort


BASH = _find_bash()
DB_PATH = VAULT_ROOT / "data" / "decisions.db"

app = FastAPI(title="Second Brain Pipeline API", version="1.0")


def run_script(command: str) -> dict:
    """Run a cns.sh sub-command and return stdout/stderr + exit code."""
    if not CNS.exists():
        raise HTTPException(status_code=503, detail=f"cns.sh not found at {CNS}")

    result = subprocess.run(
        [BASH, str(CNS), command],
        capture_output=True,
        text=True,
        timeout=300,
        env={**os.environ, "VAULT_ROOT": str(VAULT_ROOT)},
    )
    return {
        "command": command,
        "exit_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "ok": result.returncode == 0,
        "timestamp": datetime.now().isoformat(),
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "vault": str(VAULT_ROOT),
        "vault_exists": VAULT_ROOT.exists(),
        "cns_exists": CNS.exists(),
    }


@app.post("/intake")
def run_intake():
    return JSONResponse(run_script("intake"))


@app.post("/process")
def run_process():
    return JSONResponse(run_script("process"))


@app.post("/sync")
def run_sync():
    return JSONResponse(run_script("sync"))


@app.post("/snapshot")
def run_snapshot():
    return JSONResponse(run_script("snapshot"))


@app.post("/all")
def run_all():
    return JSONResponse(run_script("all"))


@app.get("/brief")
def get_brief():
    """Return a structured brief from decisions.db + inbox counts."""
    out = {"timestamp": datetime.now().isoformat(), "vault": str(VAULT_ROOT)}

    # Inbox counts
    inbox = VAULT_ROOT / "00-inbox"
    out["inbox"] = {}
    for sub in ["claude-sessions", "gmail", "transcripts", "agent-logs"]:
        subdir = inbox / sub
        files = list(subdir.glob("*.md")) if subdir.exists() else []
        tagged = sum(1 for f in files if "tagged: true" in f.read_text(errors="ignore"))
        out["inbox"][sub] = {"total": len(files), "untagged": len(files) - tagged}

    # Logseq counts
    pages = list((VAULT_ROOT / "01-logseq" / "pages").glob("*.md")) if (VAULT_ROOT / "01-logseq" / "pages").exists() else []
    journals = list((VAULT_ROOT / "01-logseq" / "journals").glob("*.md")) if (VAULT_ROOT / "01-logseq" / "journals").exists() else []
    out["logseq"] = {"pages": len(pages), "journals": len(journals)}

    # decisions.db
    if DB_PATH.exists():
        try:
            con = sqlite3.connect(DB_PATH)
            con.row_factory = sqlite3.Row
            cur = con.cursor()
            cols = [r[1] for r in cur.execute("PRAGMA table_info(decisions)").fetchall()]
            ts_col = "ts" if "ts" in cols else "created_at"
            name_col = "original" if "original" in cols else "original_name"
            total = cur.execute("SELECT COUNT(*) FROM decisions").fetchone()[0]
            approved = cur.execute("SELECT COUNT(*) FROM decisions WHERE approved=1").fetchone()[0]
            recent_row = cur.execute(
                f"SELECT {name_col}, {ts_col} FROM decisions ORDER BY {ts_col} DESC LIMIT 1"
            ).fetchone()
            out["decisions"] = {
                "total": total,
                "approved": approved,
                "last_file": recent_row[0] if recent_row else None,
                "last_ts": recent_row[1] if recent_row else None,
            }
            con.close()
        except Exception as e:
            out["decisions"] = {"error": str(e)}
    else:
        out["decisions"] = {"error": "decisions.db not found"}

    return JSONResponse(out)
