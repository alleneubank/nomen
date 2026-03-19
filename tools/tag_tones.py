#!/usr/bin/env python3
"""Tag words with tones and expand category lists for nomen.

Reads src/data/words.tsv (word\tpos\ttheme), adds tone column and new words,
writes updated TSV (word\tpos\ttheme\ttone).

Tones: nature, tech, general (empty = general)
"""

import sys
from pathlib import Path
from nltk.corpus import wordnet as wn

# Nature-associated WordNet hypernyms (lemma names in hypernym chains)
NATURE_HYPERNYMS = {
    "natural_object", "geological_formation", "body_of_water", "plant",
    "animal", "bird", "fish", "mineral", "celestial_body", "weather",
    "mountain", "river", "ocean", "forest", "desert", "island", "volcano",
    "storm", "cloud", "wind", "star", "moon", "stone", "rock", "tree",
    "flower", "organism", "artifact", "land", "region", "location",
    "geographical_area", "natural_elevation", "natural_depression",
}

TECH_HYPERNYMS = {
    "machine", "device", "computer", "network", "system", "program",
    "software", "circuit", "signal", "data", "code", "digital",
    "electronic", "communication", "instrument", "mechanism",
}

# Manual overrides for words that WordNet misclassifies
NATURE_WORDS = {
    "alpine", "arctic", "coral", "crystal", "frozen", "glacier",
    "golden", "granite", "lunar", "marine", "solar", "tropical",
    "volcanic", "wild", "amber", "emerald", "ivory", "jade",
    "obsidian", "bronze", "copper", "silver", "cobalt", "nickel",
    "carbon", "sulfur", "silicon", "iron",
    # category words are always nature
}

TECH_WORDS = {
    "binary", "digital", "cyber", "quantum", "atomic", "nuclear",
    "electric", "magnetic", "sonic", "laser", "radar", "radio",
    "plasma", "micro", "macro", "mega", "ultra", "nano", "pixel",
    "modem", "robot", "android", "virtual", "stereo", "video",
    "audio", "turbo", "nitro", "diesel", "hybrid",
}


def get_hypernym_chain(word):
    """Get all hypernym lemma names for a word."""
    lemmas = set()
    for synset in wn.synsets(word):
        for path in synset.hypernym_paths():
            for s in path:
                for lemma in s.lemmas():
                    lemmas.add(lemma.name().lower())
    return lemmas


def classify_tone(word, theme):
    """Classify a word's tone as nature, tech, or general."""
    # Words with themes are always nature
    if theme:
        return "nature"

    # Manual overrides
    if word in NATURE_WORDS:
        return "nature"
    if word in TECH_WORDS:
        return "tech"

    # Check WordNet hypernym chains
    hypernyms = get_hypernym_chain(word)
    nature_score = len(hypernyms & NATURE_HYPERNYMS)
    tech_score = len(hypernyms & TECH_HYPERNYMS)

    if nature_score > tech_score and nature_score >= 2:
        return "nature"
    if tech_score > nature_score and tech_score >= 2:
        return "tech"

    return ""  # general (empty)


# New category words to add
NEW_CATEGORIES = {
    "volcanoes": [
        "vesuvius", "krakatoa", "etna", "fuji", "helens",
        "pinatubo", "tambora", "mauna", "kilauea", "rainier",
        "stromboli", "cotopaxi", "elbrus", "shasta", "katmai",
        "redoubt", "augustine", "spurr", "pavlof", "akutan",
    ],
    "forests": [
        "sequoia", "redwood", "boreal", "taiga", "mangrove",
        "bamboo", "cypress", "cedar", "hemlock", "spruce",
        "birch", "aspen", "maple", "juniper", "willow",
        "sycamore", "hickory", "mahogany", "teak", "ebony",
    ],
    "oceans": [
        "pacific", "atlantic", "arctic", "indian", "mariana",
        "bermuda", "coral", "bering", "sargasso", "adriatic",
        "aegean", "caspian", "baltic", "andaman", "tasman",
        "timor", "celebes", "banda", "arafura", "beaufort",
    ],
    "storms": [
        "typhoon", "cyclone", "tornado", "monsoon", "tempest",
        "blizzard", "squall", "gale", "mistral", "sirocco",
        "chinook", "zephyr", "bora", "foehn", "harmattan",
        "derecho", "haboob", "norther", "pampero", "levanter",
    ],
}

# Additional words to expand existing categories
EXPAND_EXISTING = {
    "mountains": [
        "olympus", "fuji", "baker", "adams", "teton",
        "maroon", "crestone", "sopris", "yale", "belford",
        "tabeguache", "antero", "grays", "torreys", "castle",
    ],
    "rivers": [
        "amazon", "danube", "thames", "ganges", "nile",
        "tigris", "volga", "rhine", "seine", "elbe",
        "mekong", "yangtze", "zambezi", "murray", "fraser",
    ],
    "deserts": [
        "sahara", "gobi", "kalahari", "atacama", "simpson",
        "negev", "ordos", "thar", "dasht", "kavir",
    ],
    "canyons": [
        "glen", "grand", "copper", "waimea", "colca",
        "blyde", "verdon", "gorge", "narrows", "slot",
    ],
    "islands": [
        "bermuda", "corsica", "crete", "fiji", "guam",
        "java", "borneo", "sumatra", "luzon", "mindanao",
        "tahiti", "tonga", "samoa", "palau", "nauru",
    ],
    "passes": [
        "brenner", "khyber", "simplon", "furka", "stelvio",
        "gotthard", "bernina", "julier", "spluga", "maloja",
    ],
    "moons": [
        "ganymede", "io", "enceladus", "mimas", "dione",
        "tethys", "iapetus", "phoebe", "nereid", "proteus",
    ],
    "raptors": [
        "peregrine", "gyrfalcon", "saker", "lanner", "eleonora",
        "aplomado", "shikra", "accipiter", "buteo", "aquila",
    ],
    "minerals": [
        "obsidian", "jasper", "onyx", "opal", "jade",
        "ruby", "sapphire", "diamond", "emerald", "amber",
        "malachite", "turquoise", "lapis", "citrine", "amethyst",
    ],
    "norse": [
        "fenrir", "jormun", "sleipnir", "mjolnir", "yggdra",
        "bifrost", "asgard", "midgard", "ragnar", "sigurd",
        "gungnir", "huginn", "muninn", "norns", "valkyrie",
    ],
}


def main():
    tsv_path = Path(__file__).parent.parent / "src" / "data" / "words.tsv"

    # Read existing words
    existing = {}  # word -> (pos, theme)
    with open(tsv_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            word = parts[0]
            pos = parts[1] if len(parts) > 1 else "n"
            theme = parts[2] if len(parts) > 2 else ""
            existing[word] = (pos, theme)

    print(f"Existing words: {len(existing)}", file=sys.stderr)

    # Add new category words
    added = 0
    for cat, words in {**NEW_CATEGORIES, **EXPAND_EXISTING}.items():
        for word in words:
            word = word.lower().strip()
            if not word or len(word) > 12 or not word.isalpha():
                continue
            if word in existing:
                # Update theme if word exists but has no theme
                pos, theme = existing[word]
                if not theme:
                    existing[word] = (pos, cat)
            else:
                # New word — get POS from WordNet
                synsets = wn.synsets(word)
                if synsets:
                    pos_map = {wn.NOUN: 'n', wn.VERB: 'v', wn.ADJ: 'a', wn.ADJ_SAT: 'a'}
                    tags = sorted(set(pos_map.get(s.pos(), '?') for s in synsets))
                    tags = [t for t in tags if t in ('a', 'n', 'v')]
                    pos = ','.join(tags) if tags else 'n'
                else:
                    pos = 'p'  # proper noun
                existing[word] = (pos, cat)
                added += 1

    print(f"Added {added} new words", file=sys.stderr)

    # Classify tones
    result = {}
    for word, (pos, theme) in existing.items():
        tone = classify_tone(word, theme)
        result[word] = (pos, theme, tone)

    # Count tones
    from collections import Counter
    tone_counts = Counter(t for _, (_, _, t) in result.items())
    print(f"Tones: {dict(tone_counts)}", file=sys.stderr)

    # Count per category
    cat_counts = Counter()
    for _, (_, theme, _) in result.items():
        if theme:
            cat_counts[theme] += 1
    print(f"Categories: {dict(sorted(cat_counts.items()))}", file=sys.stderr)

    # Write updated TSV (sorted)
    with open(tsv_path, 'w') as f:
        for word in sorted(result.keys()):
            pos, theme, tone = result[word]
            f.write(f"{word}\t{pos}\t{theme}\t{tone}\n")

    print(f"Wrote {len(result)} words to {tsv_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
