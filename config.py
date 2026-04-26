from pathlib import Path
import os

ROOT = Path(__file__).parent

# Read .env manually — avoids dotenv path/encoding issues on Windows
_env_file = ROOT / ".env"
if _env_file.exists():
    for _line in _env_file.read_text(encoding="utf-8").splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip())

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
EAGLE_API_URL = os.getenv("EAGLE_API_URL", "http://localhost:41595")
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434")
AGENT_USER_ID = os.getenv("AGENT_USER_ID", "kenneth")
INTAKE_BATCH_SIZE = int(os.getenv("INTAKE_BATCH_SIZE", "15"))
AUTO_SUGGEST_THRESHOLD = float(os.getenv("AUTO_SUGGEST_THRESHOLD", "0.90"))

DB_PATH = ROOT / "data" / "decisions.db"
CLAUDE_MD_PATH = ROOT / "CLAUDE.md"

PRIMARY_MODEL = "claude-sonnet-4-6"
VISION_MODEL = "llava:7b"
FAST_MODEL = "llama3.2:3b"

EAGLE_STAGING_FOLDER = "The Pile"

TAG_PREFIXES = ["use:", "topic:", "src:", "status:", "q:", "proj:"]

CONFIDENCE_THRESHOLDS = {
    "auto_suggest": AUTO_SUGGEST_THRESHOLD,
    "require_approval": 0.70,
    "flag_uncertain": 0.50,
}
