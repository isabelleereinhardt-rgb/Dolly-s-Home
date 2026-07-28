#!/usr/bin/env python3
"""
build_rbxmx.py
--------------------------------------------------------------------------
Packages src/ into three .rbxmx files you drag straight into Roblox Studio.

This exists so you never have to install Rojo. .rbxmx is Roblox's own XML
model format: right-click a service in the Explorer, "Insert from File", pick
the file, done. The folder structure inside the file is the folder structure
you get in Studio.

    build/DollysHome_ReplicatedStorage.rbxmx   -> ReplicatedStorage
    build/DollysHome_ServerScriptService.rbxmx -> ServerScriptService
    build/DollysHome_StarterPlayerScripts.rbxmx-> StarterPlayer/StarterPlayerScripts

Naming rules, matching how Rojo reads a directory:

    init.server.luau  -> the folder itself becomes a Script
    init.client.luau  -> the folder itself becomes a LocalScript
    anything.luau     -> a ModuleScript
    a directory       -> a Folder (unless it holds an init file)

Run:  python3 tools/build_rbxmx.py
--------------------------------------------------------------------------
"""

from __future__ import annotations

import html
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "src"
OUT = REPO / "build"

# Which source directory goes to which Roblox service, and what the top-level
# instance is called once it lands there.
BUNDLES = [
    {
        "source": SRC / "shared",
        "name": "Shared",
        "file": "DollysHome_ReplicatedStorage.rbxmx",
        "destination": "ReplicatedStorage",
    },
    {
        "source": SRC / "server",
        "name": "DollysHome",
        "file": "DollysHome_ServerScriptService.rbxmx",
        "destination": "ServerScriptService",
    },
    {
        "source": SRC / "client",
        "name": "DollysHomeClient",
        "file": "DollysHome_StarterPlayerScripts.rbxmx",
        "destination": "StarterPlayer > StarterPlayerScripts",
    },
]

_referent = 0


def next_referent() -> str:
    global _referent
    _referent += 1
    return f"RBX{_referent}"


def cdata(source: str) -> str:
    """
    Wraps Luau source in CDATA.

    A CDATA section cannot contain the literal ']]>'. Luau long-bracket
    comments end in ']]', so a comment closing immediately before a '>' would
    break the file. The standard escape is to end the section, emit the '>' in
    its own section, and reopen -- the parser stitches them back together.
    """
    escaped = source.replace("]]>", "]]]]><![CDATA[>")
    return f"<![CDATA[{escaped}]]>"


def script_class(directory: pathlib.Path) -> tuple[str, pathlib.Path | None]:
    """Returns (className, initFile) for a directory."""
    for filename, class_name in (
        ("init.server.luau", "Script"),
        ("init.client.luau", "LocalScript"),
        ("init.luau", "ModuleScript"),
    ):
        candidate = directory / filename
        if candidate.exists():
            return class_name, candidate
    return "Folder", None


def emit_item(class_name: str, name: str, source: str | None, children: list[str], depth: int) -> str:
    pad = "\t" * depth
    inner = "\t" * (depth + 1)
    prop = "\t" * (depth + 2)

    lines = [f'{pad}<Item class="{class_name}" referent="{next_referent()}">']
    lines.append(f"{inner}<Properties>")
    lines.append(f'{prop}<string name="Name">{html.escape(name)}</string>')
    if source is not None:
        lines.append(f'{prop}<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
        # Legacy run context: a Script in ServerScriptService runs on the
        # server, a LocalScript in StarterPlayerScripts runs on the client.
        # That is exactly what we want, and it is the default.
    lines.append(f"{inner}</Properties>")
    lines.extend(children)
    lines.append(f"{pad}</Item>")
    return "\n".join(lines)


def build_directory(directory: pathlib.Path, name: str, depth: int) -> str:
    class_name, init_file = script_class(directory)
    source = init_file.read_text(encoding="utf-8") if init_file else None

    children: list[str] = []

    for entry in sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name.lower())):
        if entry.name.startswith(".") or entry == init_file:
            continue

        if entry.is_dir():
            children.append(build_directory(entry, entry.name, depth + 1))
        elif entry.suffix == ".luau":
            # `Foo.server.luau` / `Foo.client.luau` are Script / LocalScript.
            stem = entry.stem
            child_class = "ModuleScript"
            if stem.endswith(".server"):
                child_class, stem = "Script", stem[: -len(".server")]
            elif stem.endswith(".client"):
                child_class, stem = "LocalScript", stem[: -len(".client")]

            children.append(
                emit_item(
                    child_class,
                    stem,
                    entry.read_text(encoding="utf-8"),
                    [],
                    depth + 1,
                )
            )

    return emit_item(class_name, name, source, children, depth)


HEADER = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
)


# Which service each bundle's root instance is parented to inside a place file.
PLACE_LAYOUT = [
    ("ReplicatedStorage", SRC / "shared", "Shared"),
    ("ServerScriptService", SRC / "server", "DollysHome"),
    # StarterPlayerScripts is nested inside StarterPlayer, handled specially.
]


def build_place() -> str:
    """
    Emits a complete .rbxlx place file -- the whole game as one document you
    open in Studio, no importing at all.

    Only the script containers are written. Lighting, Players.RespawnTime and
    everything else are applied at runtime by init.server.luau, and the map and
    lobby are built procedurally on startup, so there is no geometry to encode
    here.
    """
    services: list[str] = []

    def service(class_name: str, children: list[str]) -> str:
        return emit_item(class_name, class_name, None, children, 1)

    # Workspace, Players, Lighting and friends are created by Studio when it
    # opens a place that omits them, so only the ones holding our code matter.
    services.append(service("ReplicatedStorage", [build_directory(SRC / "shared", "Shared", 2)]))
    services.append(service("ServerScriptService", [build_directory(SRC / "server", "DollysHome", 2)]))

    starter_scripts = emit_item(
        "StarterPlayerScripts",
        "StarterPlayerScripts",
        None,
        [build_directory(SRC / "client", "DollysHomeClient", 3)],
        2,
    )
    services.append(service("StarterPlayer", [starter_scripts]))

    return f"{HEADER}\n" + "\n".join(services) + "\n</roblox>\n"


def main() -> int:
    if not SRC.is_dir():
        print(f"error: {SRC} not found -- run this from the repo root", file=sys.stderr)
        return 1

    OUT.mkdir(exist_ok=True)
    print("Building Roblox model files\n")

    for bundle in BUNDLES:
        source_dir: pathlib.Path = bundle["source"]
        if not source_dir.is_dir():
            print(f"  skipped {source_dir.name}: not found")
            continue

        body = build_directory(source_dir, bundle["name"], 1)
        document = f"{HEADER}\n{body}\n</roblox>\n"

        target = OUT / bundle["file"]
        target.write_text(document, encoding="utf-8")

        script_count = len(list(source_dir.rglob("*.luau")))
        size_kb = target.stat().st_size / 1024
        print(f"  {bundle['file']}")
        print(f"      {script_count:>2} scripts, {size_kb:>6.1f} KB  ->  {bundle['destination']}")

    # The whole game as a single openable place.
    place = OUT / "DollysHome.rbxlx"
    place.write_text(build_place(), encoding="utf-8")
    total_scripts = len(list(SRC.rglob("*.luau")))
    print(f"\n  DollysHome.rbxlx")
    print(f"      {total_scripts:>2} scripts, {place.stat().st_size / 1024:>6.1f} KB  ->  open it directly in Studio")

    print("\nEasiest: double-click DollysHome.rbxlx.")
    print("Or, to add to an existing place: right-click the service, 'Insert from File'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
