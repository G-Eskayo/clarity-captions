"""Build the engine scoreboard: aggregate all source parsers and render outputs."""
import datetime
import json
import logging
from pathlib import Path
from typing import Optional

from . import sources
from .model import Row


logger = logging.getLogger(__name__)


def build(root: Path, meta: Optional[dict] = None) -> list[Row]:
	"""Build scoreboard: call all six source parsers and return aggregated rows.

	Each parser failure is logged but never fatal—the builder continues if a source is missing.

	Args:
		root: Path to docs/perf/ or similar root directory containing source markdown files.
		meta: Optional metadata dict (e.g., {"generated_at": datetime object}). If not provided,
		      current time is used and can be overridden in render functions.

	Returns:
		List of Row objects, deduplicated and sorted by (language, task, engine, device).
	"""

	all_rows = []

	# Call all six parsers
	parsers = [
		("engine_accuracy", sources.parse_engine_accuracy),
		("language_accuracy", sources.parse_language_accuracy),
		("hebrew", sources.parse_hebrew),
		("translation", sources.parse_translation),
		("ear_translation", sources.parse_ear_translation),
		("low_bit", sources.parse_low_bit),
	]

	for name, parser in parsers:
		try:
			rows = parser(root)
			all_rows.extend(rows)
			logger.info(f"Parser {name}: {len(rows)} rows")
		except Exception as e:
			logger.error(f"Parser {name} failed: {e}", exc_info=True)

	# Deduplicate: keep first occurrence of each (language, task, engine, device, metric_name, notes)
	# Include metric_name and notes to avoid collapsing rows with different metrics or datasets
	seen = set()
	dedup_rows = []
	for row in all_rows:
		key = (row.language, row.task, row.engine, row.device_or_platform, row.metric_name, row.notes)
		if key not in seen:
			seen.add(key)
			dedup_rows.append(row)

	return dedup_rows


def render_markdown(rows: list[Row]) -> str:
	"""Render scoreboard rows as GitHub-flavored markdown tables.

	Groups rows by task, then by language within each task.
	"""

	if not rows:
		return "# Engine Scoreboard\n\nNo data yet.\n"

	output = ["# Engine Scoreboard"]
	output.append("")
	output.append("Unified performance data for engine choice across captions, translation, and in-ear voice.")
	output.append("Sources: #145, #158, #201, #159, #237, #200. Routing, gaps, Android column, and size cleanup deferred to later steps.")
	output.append("")

	# Group by task
	by_task = {}
	for row in rows:
		if row.task not in by_task:
			by_task[row.task] = []
		by_task[row.task].append(row)

	# Render each task section in order
	task_rows = by_task.get("captions", [])
	if task_rows:
		output.append("## Captions")
		output.append("")

		# Group by language
		by_lang = {}
		for row in task_rows:
			if row.language not in by_lang:
				by_lang[row.language] = []
			by_lang[row.language].append(row)

		for lang in sorted(by_lang.keys()):
			output.append(f"### {lang}")
			output.append("")

			# Render table
			headers = ["Engine", "WER", "95% CI", "Device"]
			output.append("| " + " | ".join(headers) + " |")
			output.append("|---|---|---|---|")

			for row in sorted(by_lang[lang], key=lambda r: (r.metric_value or 0, r.engine)):
				wer_str = f"{row.metric_value*100:.1f}%" if row.metric_value is not None else "–"
				ci_str = ""
				if row.ci_low is not None and row.ci_high is not None:
					ci_str = f"{row.ci_low*100:.1f}%–{row.ci_high*100:.1f}%"
				elif row.ci_low is not None:
					ci_str = f"{row.ci_low*100:.1f}%"

				output.append(f"| {row.engine} | {wer_str} | {ci_str} | {row.device_or_platform} |")

			output.append("")

	# Translation section
	translation_rows = by_task.get("translation", [])
	if translation_rows:
		output.append("## Translation")
		output.append("")

		headers = ["Engine", "Language pair", "chrF", "95% CI", "Device"]
		output.append("| " + " | ".join(headers) + " |")
		output.append("|---|---|---|---|---|")

		for row in sorted(translation_rows, key=lambda r: (r.language, r.engine)):
			chrf_str = f"{row.metric_value:.1f}" if row.metric_value is not None else "–"
			ci_str = ""
			if row.ci_low is not None and row.ci_high is not None:
				ci_str = f"{row.ci_low:.1f}–{row.ci_high:.1f}"

			output.append(f"| {row.engine} | {row.language} | {chrf_str} | {ci_str} | {row.device_or_platform} |")

		output.append("")

	# Ear translation section
	ear_rows = by_task.get("ear-translation", [])
	if ear_rows:
		output.append("## In-Ear Voice Translation")
		output.append("")

		headers = ["Engine", "Component", "Latency (ms)", "Device"]
		output.append("| " + " | ".join(headers) + " |")
		output.append("|---|---|---|---|")

		for row in sorted(ear_rows, key=lambda r: (r.metric_value or 0, r.engine)):
			latency_str = f"{row.metric_value:.0f}" if row.metric_value is not None else "–"
			output.append(f"| {row.engine} | {row.notes} | {latency_str} | {row.device_or_platform} |")

		output.append("")

	# Model size section
	size_rows = by_task.get("model-size", [])
	if size_rows:
		output.append("## Model Sizes")
		output.append("")

		headers = ["Model", "On disk (MB)", "Compressed (MB)", "Device"]
		output.append("| " + " | ".join(headers) + " |")
		output.append("|---|---:|---:|---|")

		for row in sorted(size_rows, key=lambda r: r.engine):
			disk_str = f"{row.size_on_disk_mb:.1f}" if row.size_on_disk_mb is not None else "–"
			compressed_str = f"{row.size_zipped_mb:.1f}" if row.size_zipped_mb is not None else "–"
			output.append(f"| {row.engine} | {disk_str} | {compressed_str} | {row.device_or_platform} |")

		output.append("")

	return "\n".join(output)


def render_json(rows: list[Row], meta: Optional[dict] = None) -> str:
	"""Render scoreboard rows as JSON.

	Each row is a dict with all fields (nulls for missing values).
	Top-level object has 'meta' and 'rows' keys.
	"""

	if meta is None:
		meta = {}

	if "generated_at" not in meta:
		meta["generated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()

	row_dicts = []
	for row in rows:
		row_dicts.append({
			"language": row.language,
			"task": row.task,
			"engine": row.engine,
			"device_or_platform": row.device_or_platform,
			"metric_name": row.metric_name,
			"metric_value": row.metric_value,
			"ci_low": row.ci_low,
			"ci_high": row.ci_high,
			"size_on_disk_mb": row.size_on_disk_mb,
			"size_zipped_mb": row.size_zipped_mb,
			"latency": row.latency,
			"memory_mb": row.memory_mb,
			"source_ticket": row.source_ticket,
			"source_doc": row.source_doc,
			"notes": row.notes,
		})

	output = {
		"meta": meta,
		"rows": row_dicts,
	}

	return json.dumps(output, indent=2)
