"""Builds Packages/LoweyCore/Sources/LoweyCore/Resources/visemes.txt from the CMU Pronouncing Dictionary.

Each line: `word shapes` - one letter per phoneme, the 14 mouth shapes of Adobe Character Animator's set (MouthShape):
  a Ah (AA AE AW AY)   e Ee (IY IH EY EH)   o Oh (AO OW OY)   u Uh (AH UH, and HH)   w W-Oo (UW W)   r R (ER R)
  m M (M B P)          f F (F V)            l L (L)           s S (S Z SH ZH CH JH)  d D (D T N K G NG Y TH DH)
Vowels are lower-case, consonants upper-case (vowels get more time when a word is spread over its duration). The nine
Rhubarb shapes (Viseme) are read from these (MouthShape.viseme).

Usage: python Tools/make_visemes.py cmudict.dict
CMUdict: https://github.com/cmusphinx/cmudict (BSD 2-clause, see THIRD_PARTY.md).
"""
import re
import sys

VOWELS = {
    "AA": "a", "AE": "a", "AH": "u", "AO": "o", "AW": "a", "AY": "a", "EH": "e", "ER": "r", "EY": "e",
    "IH": "e", "IY": "e", "OW": "o", "OY": "o", "UH": "u", "UW": "w",
}
CONSONANTS = {
    "B": "M", "M": "M", "P": "M", "F": "F", "V": "F", "L": "L", "W": "W", "R": "R",
    "CH": "S", "JH": "S", "SH": "S", "ZH": "S", "S": "S", "Z": "S",
    "D": "D", "T": "D", "N": "D", "K": "D", "G": "D", "NG": "D", "Y": "D", "TH": "D", "DH": "D", "HH": "U",
}


def main(path, out):
    seen = set()
    lines = []
    with open(path, encoding="utf-8") as source:
        for raw in source:
            raw = raw.split("#")[0].strip()
            if not raw:
                continue
            word, *phones = raw.split()
            if "(" in word or word in seen or not re.fullmatch(r"[a-z']{1,20}", word):
                continue
            visemes = []
            for phone in phones:
                base = re.sub(r"\d", "", phone)
                visemes.append(VOWELS.get(base) or CONSONANTS.get(base) or "D")
            seen.add(word)
            lines.append(f"{word} {''.join(visemes)}")
    lines.sort()
    with open(out, "w", encoding="utf-8", newline="\n") as target:
        target.write("\n".join(lines) + "\n")
    print(f"{len(lines)} words")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Packages/LoweyCore/Sources/LoweyCore/Resources/visemes.txt")
