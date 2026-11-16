"""Parsers for the six scoreboard sources: six committed markdown docs with results tables.

Each parser reads a specific docs/perf/*.md file and returns a list of Row.
Failures are logged and isolated—a missing or malformed source never crashes the builder.
"""
import logging
import re
from pathlib import Path
from typing import Optional

from .md_table import parse_tables
from .model import Row


logger = logging.getLogger(__name__)


def parse_engine_accuracy(root: Path) -> list[Row]:
	"""Parse engine-accuracy-comparison.md (#145 EdAcc test).

	Extracts: engines, WER %, and confidence interval bounds from the "Overall" table.
	Device: iPhone (default when not specified).
	Language: English (multi-accent).
	Task: captions.
	"""
	path = root / "engine-accuracy-comparison.md"
	if not path.exists():
		logger.warning(f"Engine accuracy source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	# First table should be "Overall"
	for table in tables:
		if not table.rows:
			continue

		# Look for Engine and WER columns
		headers_lower = [h.lower() for h in table.headers]
		if "engine" not in headers_lower or "wer" not in headers_lower:
			continue

		engine_idx = headers_lower.index("engine")
		wer_idx = headers_lower.index("wer")
		ci_idx = None
		if "95% ci" in headers_lower:
			ci_idx = headers_lower.index("95% ci")

		for row_dict in table.rows:
			engine = row_dict.get(table.headers[engine_idx], "").strip()
			wer_str = row_dict.get(table.headers[wer_idx], "").strip()
			ci_str = row_dict.get(table.headers[ci_idx], "").strip() if ci_idx is not None else ""

			if not engine or not wer_str:
				continue

			# Skip diagnostic/dropped entries
			if "diagnostic" in engine.lower() or "dropped" in engine.lower():
				continue

			# Parse WER (e.g., "13.8%")
			wer_match = re.search(r'([\d.]+)\s*%', wer_str)
			if not wer_match:
				continue
			wer = float(wer_match.group(1)) / 100.0

			# Parse CI bounds from e.g. "12.7% – 14.7%"
			ci_low, ci_high = None, None
			if ci_str:
				ci_parts = re.findall(r'([\d.]+)\s*%', ci_str)
				if len(ci_parts) >= 2:
					ci_low = float(ci_parts[0]) / 100.0
					ci_high = float(ci_parts[1]) / 100.0

			rows.append(Row(
				language="English",
				task="captions",
				engine=engine,
				device_or_platform="iPhone",
				metric_name="WER",
				metric_value=wer,
				ci_low=ci_low,
				ci_high=ci_high,
				source_ticket="#145",
				source_doc="engine-accuracy-comparison.md",
			))

		# Only process the first suitable table (Overall)
		if rows:
			break

	return rows


def parse_language_accuracy(root: Path) -> list[Row]:
	"""Parse language-accuracy-comparison.md (#158 FLEURS test).

	Extracts: engines, WER %, CI for each language (Spanish, French, German, Italian, Portuguese).
	Excludes Android-path ONNX results per decision d2 (deferred to step 4).
	Device: Mac (FLEURS is read speech on Mac).
	Task: captions.
	"""
	path = root / "language-accuracy-comparison.md"
	if not path.exists():
		logger.warning(f"Language accuracy source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	# Track index of data tables only (not empty or non-data tables)
	data_table_index = 0

	# Each language section has its own table. Parse them in order.
	for table in tables:
		if not table.rows:
			continue

		headers_lower = [h.lower() for h in table.headers]
		if "engine" not in headers_lower or "wer" not in headers_lower:
			continue

		# If it's the summary table, skip (has "Recommendation" column)
		if "recommendation" in headers_lower:
			continue

		engine_idx = headers_lower.index("engine")
		wer_idx = headers_lower.index("wer")
		ci_idx = None
		if "95% ci" in headers_lower:
			ci_idx = headers_lower.index("95% ci")

		# Infer language from the table index and expected order
		lang = _infer_language_from_section(text, data_table_index)
		if not lang:
			lang = "Unknown"

		for row_dict in table.rows:
			engine = row_dict.get(table.headers[engine_idx], "").strip()

			# Note: Android-path ONNX results are tested on Mac here but would be Android paths
			# in production. Decision d2 (whether to exclude them) is deferred to step 4.
			# Currently included—they're labeled device_or_platform="Mac" since they run on Mac.

			# Extract WER
			wer_str = row_dict.get(table.headers[wer_idx], "").strip()
			if not engine or not wer_str:
				continue

			wer_match = re.search(r'([\d.]+)\s*%', wer_str)
			if not wer_match:
				continue
			wer = float(wer_match.group(1)) / 100.0

			ci_low, ci_high = None, None
			if ci_idx is not None:
				ci_str = row_dict.get(table.headers[ci_idx], "").strip()
				if ci_str:
					ci_parts = re.findall(r'([\d.]+)\s*%', ci_str)
					if len(ci_parts) >= 2:
						ci_low = float(ci_parts[0]) / 100.0
						ci_high = float(ci_parts[1]) / 100.0

			rows.append(Row(
				language=lang,
				task="captions",
				engine=engine,
				device_or_platform="Mac",
				metric_name="WER",
				metric_value=wer,
				ci_low=ci_low,
				ci_high=ci_high,
				source_ticket="#158",
				source_doc="language-accuracy-comparison.md",
			))

		data_table_index += 1

	return rows


def _infer_language_from_section(text: str, table_index: int) -> Optional[str]:
	"""Infer language from the markdown section context by table index.

	Looks for language section headers (## Spanish, ## French, etc) and
	maps them to data tables in order.
	"""
	section_patterns = [
		(r'## Spanish', 'Spanish'),
		(r'## French', 'French'),
		(r'## German', 'German'),
		(r'## Italian', 'Italian'),
		(r'## Portuguese', 'Portuguese'),
	]

	# Find all section positions
	sections = []
	for pattern, lang in section_patterns:
		match = re.search(pattern, text)
		if match:
			sections.append((match.start(), lang))

	# Sort by position and return the table_index-th language
	sections.sort(key=lambda x: x[0])
	if table_index < len(sections):
		return sections[table_index][1]

	return None


def parse_hebrew(root: Path) -> list[Row]:
	"""Parse hebrew-accuracy-comparison.md (#201 Hebrew test).

	Extracts: engines, WER % and CER (character error rate) from each dataset.
	Device: Mac (all tests run on M4 Mac mini).
	Language: Hebrew.
	Task: captions.
	"""
	path = root / "hebrew-accuracy-comparison.md"
	if not path.exists():
		logger.warning(f"Hebrew accuracy source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	# Each dataset (eval-d1, eval-whatsapp, FLEURS) has its own table
	dataset_names = ["ivrit.ai eval-d1", "ivrit.ai eval-whatsapp", "FLEURS he"]
	dataset_index = 0

	for table in tables:
		if not table.rows:
			continue

		headers_lower = [h.lower() for h in table.headers]
		if "engine" not in headers_lower or "wer" not in headers_lower:
			continue

		# Determine dataset name (inferred from order or text context)
		dataset = dataset_names[dataset_index] if dataset_index < len(dataset_names) else f"dataset_{dataset_index}"
		dataset_index += 1

		engine_idx = headers_lower.index("engine")
		wer_idx = headers_lower.index("wer")

		# Find the first "95% CI" (for WER) - use the original headers list to handle indexed keys
		# Headers with repeated names get indexed like "95% CI__2"
		wer_ci_idx = None
		for i, h in enumerate(table.headers):
			if h == "95% CI" or h.startswith("95% CI"):
				# This should be the WER CI (first occurrence)
				wer_ci_idx = i
				break

		for row_dict in table.rows:
			engine = row_dict.get(table.headers[engine_idx], "").strip()
			wer_str = row_dict.get(table.headers[wer_idx], "").strip()

			if not engine or not wer_str:
				continue

			# Parse WER
			wer_match = re.search(r'([\d.]+)\s*%', wer_str)
			if not wer_match:
				continue
			wer = float(wer_match.group(1)) / 100.0

			ci_low, ci_high = None, None
			# Get WER CI from the correct header (using indexed key if needed)
			if wer_ci_idx is not None:
				header_key = table.headers[wer_ci_idx]
				ci_str = row_dict.get(header_key, "").strip()
				if ci_str:
					ci_parts = re.findall(r'([\d.]+)\s*%', ci_str)
					if len(ci_parts) >= 2:
						ci_low = float(ci_parts[0]) / 100.0
						ci_high = float(ci_parts[1]) / 100.0

			# Include dataset in engine name to differentiate rows from different datasets
			engine_with_dataset = f"{engine} ({dataset})"

			rows.append(Row(
				language="Hebrew",
				task="captions",
				engine=engine_with_dataset,
				device_or_platform="Mac",
				metric_name="WER",
				metric_value=wer,
				ci_low=ci_low,
				ci_high=ci_high,
				source_ticket="#201",
				source_doc="hebrew-accuracy-comparison.md",
				notes=None,
			))

	return rows


def parse_translation(root: Path) -> list[Row]:
	"""Parse translation-comparison-results.md (#159 translation test).

	Extracts: engines, chrF and COMET metrics from accuracy tables.
	Excludes ML Kit (Android emulator on Mac) per decision d2.
	Device: Mac for Apple/OPUS-MT; excluded for ML Kit.
	Language pairs: en-es, en-fr, etc.
	Task: translation.
	"""
	path = root / "translation-comparison-results.md"
	if not path.exists():
		logger.warning(f"Translation source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	# Track which data table we're in (skip non-data subtables like "vs best" columns)
	data_table_index = 0

	for table in tables:
		if not table.rows:
			continue

		headers_lower = [h.lower() for h in table.headers]
		if "engine" not in headers_lower or "chrf" not in headers_lower:
			continue

		engine_idx = headers_lower.index("engine")
		chrf_idx = headers_lower.index("chrf")
		comet_idx = headers_lower.index("comet") if "comet" in headers_lower else None

		# Infer language pair from table position
		lang_pair = _infer_language_pair(text, data_table_index)
		if not lang_pair:
			logger.warning(f"Could not infer language pair for translation table at index {data_table_index}; defaulting to 'en-es'")
			lang_pair = "en-es"

		for row_dict in table.rows:
			engine = row_dict.get(table.headers[engine_idx], "").strip()
			chrf_str = row_dict.get(table.headers[chrf_idx], "").strip()

			# Skip ML Kit rows (Android emulator on Mac - decision d2 deferred)
			if "mlkit" in engine.lower():
				continue

			if not engine or not chrf_str:
				continue

			# Parse chrF (e.g., "56.8 [56.2–57.4]" or "56.8")
			chrf_match = re.search(r'([\d.]+)', chrf_str)
			if not chrf_match:
				continue
			chrf = float(chrf_match.group(1))

			# Parse CI if brackets are present
			ci_low, ci_high = None, None
			ci_matches = re.findall(r'\[([\d.]+)–([\d.]+)\]', chrf_str)
			if ci_matches:
				ci_low = float(ci_matches[0][0])
				ci_high = float(ci_matches[0][1])

			# Parse COMET if present
			comet_value = None
			if comet_idx is not None:
				comet_str = row_dict.get(table.headers[comet_idx], "").strip()
				if comet_str:
					comet_match = re.search(r'([\d.]+)', comet_str)
					if comet_match:
						comet_value = float(comet_match.group(1))

			rows.append(Row(
				language=lang_pair,
				task="translation",
				engine=engine,
				device_or_platform="Mac",
				metric_name="chrF",
				metric_value=chrf,
				ci_low=ci_low,
				ci_high=ci_high,
				source_ticket="#159",
				source_doc="translation-comparison-results.md",
				notes=f"COMET: {comet_value}" if comet_value else None,
			))

		data_table_index += 1

	return rows


def _infer_language_pair(text: str, table_index: int) -> Optional[str]:
	"""Infer language pair from markdown section context by table index.

	Looks for language pair section headers (## en-es, ## en-fr, etc) and
	maps them to data tables in order.
	"""
	# Find all language pair section positions
	lang_pair_pattern = r'## (en-\w+)'
	pairs = []
	for match in re.finditer(lang_pair_pattern, text):
		pairs.append((match.start(), match.group(1)))

	# Sort by position and return the table_index-th pair
	pairs.sort(key=lambda x: x[0])
	if table_index < len(pairs):
		return pairs[table_index][1]

	return None


def parse_ear_translation(root: Path) -> list[Row]:
	"""Parse ear-translation-spike.md (#237 in-ear translation).

	Extracts: lag measurements from the Speech to voice lag table.
	Device: Mac (not yet on iPhone).
	Language: depends on language.
	Task: ear-translation (in-ear spoken translation lag).
	"""
	path = root / "ear-translation-spike.md"
	if not path.exists():
		logger.warning(f"Ear translation source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	# Find the "Speech to voice lag" table
	for table in tables:
		if not table.rows:
			continue

		headers_lower = [h.lower() for h in table.headers]
		# This table has "Step", "Median", "p95", "Where measured"
		if "step" not in headers_lower or ("median" not in headers_lower and "p95" not in headers_lower):
			continue

		step_idx = headers_lower.index("step") if "step" in headers_lower else None
		median_idx = headers_lower.index("median") if "median" in headers_lower else None

		for row_dict in table.rows:
			step = row_dict.get(table.headers[step_idx], "").strip() if step_idx is not None else ""

			if not step:
				continue

			# Extract median time in ms - accept any row with a time measurement
			median_str = row_dict.get(table.headers[median_idx], "").strip() if median_idx is not None else ""
			if not median_str:
				continue

			# Parse various formats: "10–61 ms", "859 ms", "10 ms", "10 ms Mac"
			# Also handle plain bold like **859 ms**. Dash and range are optional.
			ms_match = re.search(r'(\*\*)?([\d.]+)(?:\s*(?:–|-|–)\s*([\d.]+))?(\s*\*\*)?(\s*(?:ms|MB))?', median_str)
			if not ms_match:
				continue

			try:
				latency_low = float(ms_match.group(2))
				latency_high = float(ms_match.group(3)) if ms_match.group(3) else None
				latency = latency_low  # Use lower bound or average if range
				if latency_high:
					latency = (latency_low + latency_high) / 2.0

				rows.append(Row(
					language="all",
					task="ear-translation",
					engine="Apple Translation + device voice",
					device_or_platform="Mac",
					metric_name="latency_ms",
					metric_value=latency,
					source_ticket="#237",
					source_doc="ear-translation-spike.md",
					notes=step,
				))
			except (ValueError, IndexError):
				# Skip if we can't parse the latency value
				continue

	return rows


def parse_low_bit(root: Path) -> list[Row]:
	"""Parse install-size-2026-10-29.md (#200 install size).

	Extracts: model sizes (on disk, compressed) from the Results table.
	Device: iPhone/iPad (universal arm64 build).
	Language: N/A (size is hardware-agnostic).
	Task: model-size.
	"""
	path = root / "install-size-2026-10-29.md"
	if not path.exists():
		logger.warning(f"Install size source not found: {path}")
		return []

	text = path.read_text()
	tables = parse_tables(text)
	rows = []

	for table in tables:
		if not table.rows:
			continue

		headers_lower = [h.lower() for h in table.headers]
		if "part" not in headers_lower or ("on disk" not in headers_lower and "compressed" not in headers_lower):
			continue

		part_idx = headers_lower.index("part")
		disk_idx = headers_lower.index("on disk") if "on disk" in headers_lower else None
		compressed_idx = headers_lower.index("compressed (zip -9)") if "compressed (zip -9)" in headers_lower else None

		for row_dict in table.rows:
			part = row_dict.get(table.headers[part_idx], "").strip() if part_idx is not None else ""

			if not part or "everything else" in part.lower() or ".app" in part.lower():
				continue

			disk_str = row_dict.get(table.headers[disk_idx], "").strip() if disk_idx is not None else ""
			compressed_str = row_dict.get(table.headers[compressed_idx], "").strip() if compressed_idx is not None else ""

			# Parse sizes in MB (e.g., "498.0 MB" or "498 MB")
			disk_mb = None
			if disk_str:
				disk_match = re.search(r'([\d.]+)\s*MB', disk_str)
				if disk_match:
					disk_mb = float(disk_match.group(1))

			compressed_mb = None
			if compressed_str:
				compressed_match = re.search(r'([\d.]+)\s*MB', compressed_str)
				if compressed_match:
					compressed_mb = float(compressed_match.group(1))

			if disk_mb or compressed_mb:
				rows.append(Row(
					language="N/A",
					task="model-size",
					engine=part.strip(),
					device_or_platform="iPhone",
					metric_name="size_mb",
					metric_value=disk_mb or compressed_mb,
					size_on_disk_mb=disk_mb,
					size_zipped_mb=compressed_mb,
					source_ticket="#200",
					source_doc="install-size-2026-10-29.md",
				))

	return rows
