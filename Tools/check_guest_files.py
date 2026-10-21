"""G1: the guests' files open in the tools their people use.

Reads what LoweyCore's tests wrote to the acceptance folder (ACCEPTANCE_DIR) and checks:
  room/house.ifc    IfcOpenShell opens it, validates it against IFC4, and finds the walls, slab, roof, space and storeys
  room/plan.dxf     ezdxf opens and audits it with no errors and finds the cut walls on their layer
  room/plan.pdf     pypdf reads its pages
  print/*.3mf       trimesh loads each part watertight (as a slicer checks)
  study/*.pdf       pypdf reads the technical sheet
  papercraft/*      the net's PDF reads and its SVG parses

Usage: python Tools/check_guest_files.py acceptance
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def check_ifc(path: Path) -> None:
    import ifcopenshell
    import ifcopenshell.validate

    model = ifcopenshell.open(str(path))
    assert model.schema == "IFC4", model.schema
    logger = ifcopenshell.validate.json_logger()
    ifcopenshell.validate.validate(model, logger)
    problems = [s for s in logger.statements if s.get("level") == "ERROR"]
    assert not problems, problems[:5]
    for kind, least in [("IfcWall", 1), ("IfcSlab", 1), ("IfcRoof", 1), ("IfcSpace", 1), ("IfcBuildingStorey", 2),
                        ("IfcColumn", 1), ("IfcBeam", 1), ("IfcRailing", 1)]:
        found = len(model.by_type(kind))
        assert found >= least, f"{kind}: {found}"
    for wall in model.by_type("IfcWall"):
        assert wall.ContainedInStructure, "a wall sits in a storey"
    print(f"MAQUETTE: IFC ok ({len(model.by_type('IfcProduct'))} products)")


def check_dxf(path: Path) -> None:
    import ezdxf

    document = ezdxf.readfile(str(path))
    auditor = document.audit()
    assert not auditor.has_errors, [str(e) for e in auditor.errors][:5]
    layers = {entity.dxf.layer for entity in document.modelspace()}
    assert "CUT" in layers, layers
    print(f"MAQUETTE: DXF ok ({len(document.modelspace())} entities)")


def check_pdf(path: Path, least_pages: int = 1) -> None:
    from pypdf import PdfReader

    reader = PdfReader(str(path))
    assert len(reader.pages) >= least_pages, len(reader.pages)
    print(f"MAQUETTE: PDF ok ({path.name}, {len(reader.pages)} pages)")


def check_3mf(path: Path) -> None:
    import trimesh

    scene = trimesh.load(str(path))
    meshes = list(scene.geometry.values()) if hasattr(scene, "geometry") else [scene]
    assert meshes, "parts"
    for mesh in meshes:
        assert mesh.is_watertight, f"{path.name}: a part isn't watertight"
    print(f"MAQUETTE: 3MF ok ({path.name}, {len(meshes)} parts)")


def check_svg(path: Path) -> None:
    root = ET.parse(str(path)).getroot()
    assert root.tag.endswith("svg"), root.tag
    print(f"MAQUETTE: SVG ok ({path.name})")


def main(folder: str) -> None:
    base = Path(folder)
    room = base / "room"
    check_ifc(room / "house.ifc")
    check_dxf(room / "plan.dxf")
    check_pdf(room / "plan.pdf", least_pages=2)
    check_svg(room / "plan.svg")
    for path in sorted((base / "print").glob("*.3mf")) if (base / "print").exists() else []:
        check_3mf(path)
    for path in sorted((base / "study").glob("*.pdf")) if (base / "study").exists() else []:
        check_pdf(path)
    papercraft = base / "papercraft"
    if papercraft.exists():
        for path in sorted(papercraft.glob("*.pdf")):
            check_pdf(path)
        for path in sorted(papercraft.glob("*.svg")):
            check_svg(path)
    print("MAQUETTE: guest files ok")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "acceptance")
