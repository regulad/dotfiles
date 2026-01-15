from pathlib import Path
from tempfile import TemporaryDirectory
from copy import deepcopy
from json import load
from json5 import loads as loads5
from typing import Annotated

import typer
from xdg_base_dirs import xdg_config_home
from markdown_pdf import MarkdownPdf, Section

from keyboard import Keyboard


def main(
            kdl_file: Annotated[Path, typer.Argument()],
            kle_file: Annotated[Path, typer.Option()] = xdg_config_home() / "kmr" / "base.json",
            out: Annotated[Path | None, typer.Option()] = None
         ) -> None:
    if out is None:
        out = kdl_file.with_suffix(".pdf")
    
    with TemporaryDirectory() as tempdir:
        temppath = Path(tempdir)
        pdf = MarkdownPdf(toc_level=2, optimize=True)
        
        with open(kdl_file, "r") as kdl_fp:
            kdl = load(kdl_fp)
    
        # TODO: KDL schema
    
        with open(kle_file, mode="r") as kle_fp:
            # the kle format is actually a js object, not json.
            rows = [loads5(row.rstrip(",\n")) for row in kle_fp]
            kle_deserialized = Keyboard(rows)
    
        for layer in [True]:
            this_layer_keyboard = deepcopy(kle_deserialized)

            layer_name = "layer"

            # I'm too used to rust. I keep seeing copying...
            with this_layer_keyboard.render() as image:
                image_uri = temppath / f"{layer_name}.png"
                image.save(image_uri, format="PNG")
            pdf.add_section(
                Section(
                    f"""
![{layer_name}]({str(image_uri).lstrip("/")})

TODO: extra notes

TODO: bind table
                    """,
                    root="/"
                )
            ) 
        pdf.save(out)
    

if __name__ == "__main__":
    typer.run(main)
