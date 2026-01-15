# Keymap Renderer

This project takes two files, a [`keyboard-layout-editor`](https://www.keyboard-layout-editor.com/#/) format keyboard description JSON file, and a `.kdl.json` ("keybind description language") file. 

It will load the `kle` "JSON" (actually js, be sure to rename the file).

It will then render a keyboard annotated with the bind present in each key in the KDL and produce a Markdown file containing each keybind layer and a table containing additional information.

Each layer's markdown file will then be converted into PDF, and all layers for a given KDL will be merged into a final PDF file. You may then print out this PDF file or use it as reference.

Also contains a script to generate KDLs from the following sources:
- `nvim-nmap.kdl.json` (create with `uv run nvim-nmap.kdl.py -o /tmp/nvim-nmap.kdl.json`)

## Existing work

Substantial parts of the rendering code for this project are taken from [`kle_render`](https://github.com/CQCumbers/kle_render). Unfortunately, the original keyboard-layout-editor is distributed under an all rights reserved license despite being open source.

## TODO

- Additional KDL creators

