"""The tests import the pipeline's modules by name, as the scripts do."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "pipeline"))
