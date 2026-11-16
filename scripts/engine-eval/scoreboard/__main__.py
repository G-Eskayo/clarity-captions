"""Scoreboard as a runnable module: python -m scoreboard.cli build ..."""
from .cli import main
import sys

if __name__ == "__main__":
	sys.exit(main())
