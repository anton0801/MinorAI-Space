# Builds the static site into ../website. Run: python3 website_src/build.py
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
OUT = os.path.join(os.path.dirname(HERE), "website")

import home, support, privacy, misc  # noqa: E402

PAGES = {
    "index.html": home.build,
    "support/index.html": support.build,
    "privacy/index.html": privacy.build,
    "join/index.html": misc.join,
    "invite/index.html": misc.invite,
    "404.html": misc.not_found,
}

css = "".join(open(os.path.join(HERE, name)).read() for name in ("base.css", "privacy.css"))
with open(os.path.join(OUT, "assets", "style.css"), "w") as f:
    f.write(css)
print(f"assets/style.css: {len(css):,} bytes")

for path, build in PAGES.items():
    html = build()
    target = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w") as f:
        f.write(html)
    print(f"{path}: {len(html):,} bytes")
