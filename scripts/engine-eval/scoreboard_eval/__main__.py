"""Run scoreboard_eval as a module: `python -m scoreboard_eval.cli build ..."""
from scoreboard_eval.cli import main
import sys

if __name__ == "__main__":
    sys.exit(main())
