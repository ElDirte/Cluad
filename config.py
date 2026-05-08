from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv()

ROOT = Path(__file__).parent

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
NOTION_API_KEY = os.getenv("NOTION_API_KEY", "")
FILE_CATALOG_DB_ID = os.getenv("FILE_CATALOG_DB_ID", "9b6cec19-5e88-4369-ba46-d90283d4c61e")
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434")
AGENT_USER_ID = os.getenv("AGENT_USER_ID", "kenneth")
INTAKE_BATCH_SIZE = int(os.getenv("INTAKE_BATCH_SIZE", "15"))
AUTO_SUGGEST_THRESHOLD = float(os.getenv("AUTO_SUGGEST_THRESHOLD", "0.90"))

# Semicolon-separated folders to scan for new files during intake
# Example: C:\Users\Allen Watts\Pictures;C:\Users\Allen Watts\Downloads
INTAKE_FOLDERS: list[str] = [
    f.strip()
    for f in os.getenv("INTAKE_FOLDERS", r"C:\Users\Allen Watts\Pictures").split(";")
    if f.strip()
]

DB_PATH = ROOT / "data" / "decisions.db"
CLAUDE_MD_PATH = ROOT / "CLAUDE.md"

PRIMARY_MODEL = "claude-sonnet-4-6"
VISION_MODEL = "llava:7b"
FAST_MODEL = "llama3.2:3b"

TAG_PREFIXES = ["use:", "topic:", "src:", "status:", "q:", "proj:"]

CONFIDENCE_THRESHOLDS = {
    "auto_suggest": AUTO_SUGGEST_THRESHOLD,
    "require_approval": 0.70,
    "flag_uncertain": 0.50,
}
