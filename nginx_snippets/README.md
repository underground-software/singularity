# nginx config inclusions

This folder contains snippets of nginx code that get included into the overall
configuration to build the website out of modular pieces.

Each subfolder is for snippets that target a different area of the config.

Files to be included have a `.conf` extension.

Nginx will include snippets referenced by a glob in lexicographic order,
so relative ordering is controlled by using a two digit numeric prefix
like `00-whatever.conf`, `01-another.conf`, etc.
