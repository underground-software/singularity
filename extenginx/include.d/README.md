# nginx config inclusions

This folder contains snippets of nginx code for inclusion in the config.

Each subfolder is for snippets that target a different area of the config.

Files to be included should have a `.conf` extension.

Nginx will include snippets referenced by a glob in lexicographic order,
so relative ordering can be controlled by using a prefix like `00-whatever.conf`, `01-another.conf`, etc.
