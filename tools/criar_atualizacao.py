#!/usr/bin/env python3
"""Gera um pacote de atualização do Last Horizon.

Uso:  python3 tools/criar_atualizacao.py "o que mudou nesta versão"

O que faz:
1. Junta os arquivos de código e cenas (scripts/, scenes/) num .zip em updates/.
   Para cada cena ou script também grava um arquivo .remap apontando para ele,
   para que a versão nova substitua a versão convertida que vem dentro do APK.
2. Atualiza updates/manifest.json com a versão nova, o tamanho e o SHA-256.
3. Atualiza config/build no project.godot, para que um APK exportado
   depois disso já saia com essa versão e não baixe a atualização de novo.

Imagens, sons e modelos 3D novos não vão nesse pacote, porque precisam ser
importados pela Godot. Quando houver arquivos assim, exporte um APK novo.
"""
import datetime
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPDATES = ROOT / "updates"
MANIFEST = UPDATES / "manifest.json"
PROJECT = ROOT / "project.godot"
INCLUDE_DIRS = ["scripts", "scenes", "personagem", "fontes"]
TEXT_EXT = {".gd", ".tscn", ".tres", ".gdshader", ".json", ".cfg", ".txt", ".glbin", ".fonte"}
REMAP_EXT = {".gd", ".tscn", ".tres"}


def main() -> None:
    notes = " ".join(sys.argv[1:]).strip()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    version = int(manifest.get("version", 1)) + 1
    name = f"update_{version}.zip"
    out = UPDATES / name

    files = []
    for d in INCLUDE_DIRS:
        for p in sorted((ROOT / d).rglob("*")):
            if p.is_file() and p.suffix in TEXT_EXT:
                files.append(p)

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            rel = p.relative_to(ROOT).as_posix()
            z.write(p, rel)
            if p.suffix in REMAP_EXT:
                z.writestr(rel + ".remap", f'[remap]\n\npath="res://{rel}"\n')

    for old in UPDATES.glob("update_*.zip"):
        if old != out:
            old.unlink()

    data = out.read_bytes()
    manifest.update({
        "version": version,
        "file": name,
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "notes": notes,
        "date": datetime.date.today().isoformat(),
    })
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text = PROJECT.read_text(encoding="utf-8")
    text = re.sub(r"^config/build=\d+$", f"config/build={version}", text, flags=re.M)
    PROJECT.write_text(text, encoding="utf-8")

    print(f"Versão {version}: {name} ({len(data) / 1024:.1f} KB, {len(files)} arquivos)")


if __name__ == "__main__":
    main()
