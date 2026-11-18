"""Extract language comparison results from language-accuracy-comparison.md."""
import re
from typing import List
from .rows import ScenarioRow, ScoreboardSourceMissing
from .markdown_table import MarkdownTable


def extract_languages(content: str) -> List[ScenarioRow]:
    """Extract language accuracy results from language-accuracy-comparison.md.

    Extracts per-language tables from language section headers.
    Only treats headings matching known language patterns as languages;
    skips metadata sections.

    Args:
        content: Full markdown content

    Returns:
        List of ScenarioRow objects

    Raises:
        ScoreboardSourceMissing: If no language sections are found
    """
    rows = []
    order_counter = 0

    lines = content.split('\n')

    # Known language names and patterns to recognize
    # Format: English name or "Name (code)" patterns
    known_languages = {
        'Spanish', 'French', 'German', 'Italian', 'Portuguese',
        'Dutch', 'Polish', 'Russian', 'Turkish', 'Mandarin', 'Cantonese',
        'Japanese', 'Korean', 'Hindi', 'Thai', 'Vietnamese', 'Indonesian',
        'Arabic', 'Hebrew', 'Greek', 'Swedish', 'Norwegian', 'Danish',
        'Finnish', 'Czech', 'Romanian', 'Hungarian', 'Bulgarian',
        'Croatian', 'Serbian', 'Slovak', 'Slovenian', 'Lithuanian',
        'Latvian', 'Estonian', 'Ukrainian', 'Icelandic', 'Farsi',
        'Tagalog', 'Malay', 'Bengali', 'Gujarati', 'Marathi',
        'Tamil', 'Telugu', 'Kannada', 'Malayalam', 'Urdu',
    }

    # Metadata sections to skip
    skip_sections = {
        'Summary', 'Engines and models', 'Recommendation',
        'Method', 'Methods', 'Notes', 'Overview', 'Overall',
        'Introduction', 'Results', 'Evaluation', 'Analysis',
        'Reference', 'References', 'Appendix', 'Details',
    }

    # Find all language section headers
    language_sections = []
    for i, line in enumerate(lines):
        if line.startswith('## '):
            section_name = line[3:].strip()
            # Check if this looks like a language section
            # Extract base language name (e.g., "Spanish" from "Spanish (es)")
            base_name = section_name.split('(')[0].strip()
            if base_name in known_languages and section_name not in skip_sections:
                language_sections.append((i, section_name))

    if not language_sections:
        raise ScoreboardSourceMissing("No language sections found in language-accuracy-comparison.md")

    # Process each language section
    for section_idx, (line_num, lang_name) in enumerate(language_sections):
        # Find the end of this section (next section or end of content)
        if section_idx + 1 < len(language_sections):
            end_line = language_sections[section_idx + 1][0]
        else:
            end_line = len(lines)

        section_lines = lines[line_num:end_line]
        section_content = '\n'.join(section_lines)

        lang_rows = _parse_language_section(section_content, lang_name, order_counter)
        rows.extend(lang_rows)
        order_counter += len(lang_rows)

    return rows


def _parse_language_section(content: str, language: str, order_start: int) -> List[ScenarioRow]:
    """Parse a single language section."""
    rows = []
    tables = MarkdownTable.extract_all_tables(content)

    if not tables:
        return rows

    table = tables[0]

    for idx, row_data in enumerate(table.to_dict_list()):
        engine = row_data.get('Engine', '')
        wer = row_data.get('WER', '')
        ci = row_data.get('95% CI', '')

        if ci:
            value = f"{wer} ({ci})"
        else:
            value = wer

        model = None
        model_match = re.search(r'\(([^)]+)\)', engine)
        if model_match:
            model = model_match.group(1)

        rows.append(ScenarioRow(
            dataset=language,
            engine=engine,
            model=model,
            language=language,
            condition=None,
            metric='WER',
            value=value,
            source_file='docs/perf/language-accuracy-comparison.md',
            source_section=f'## {language}',
            order=order_start + idx
        ))

    return rows
