import pymupdf4llm

md = pymupdf4llm.to_markdown(
    "data/raw/Python.pdf"
)

with open(
    "data/markdown/Python.md",
    "w",
    encoding="utf-8"
) as f:
    f.write(md)

print("Done")