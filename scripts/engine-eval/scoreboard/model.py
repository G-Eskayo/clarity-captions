"""Scoreboard Row dataclass for unified performance data across sources."""
from dataclasses import dataclass
from typing import Optional


@dataclass
class Row:
	"""One row in the engine scoreboard: a single (engine × language × task × device) measurement.

	The Row schema is unified across all tasks (captions, translation, in-ear voice) to support
	later step 2's routing code, even though tasks have different metric shapes (WER%, chrF, lag_ms).
	"""

	language: str
	task: str
	engine: str
	device_or_platform: str
	metric_name: Optional[str] = None
	metric_value: Optional[float] = None
	ci_low: Optional[float] = None
	ci_high: Optional[float] = None
	size_on_disk_mb: Optional[float] = None
	size_zipped_mb: Optional[float] = None
	latency: Optional[float] = None
	memory_mb: Optional[float] = None
	source_ticket: Optional[str] = None
	source_doc: Optional[str] = None
	notes: Optional[str] = None
