#!/usr/bin/env python3
"""Convert the readable spine of an EPUB into a fixed-layout PDF snapshot.

This is a pre-1.0 bridge until the MuPDF integration is complete. It uses the
system Chrome/Chromium print-to-PDF path, so the result is deterministic for a
given browser build. It never evaluates scripts and never loads remote images.
"""
from __future__ import annotations

import base64
import html
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import unquote, urlparse


def attr(tag: str, name: str) -> str | None:
    match = re.search(rf'\b{re.escape(name)}\s*=\s*["\']([^"\']*)["\']', tag, re.I)
    return html.unescape(match.group(1)) if match else None


def find_opf(zf: zipfile.ZipFile) -> str:
    container = zf.read("META-INF/container.xml").decode("utf-8", "replace")
    match = re.search(r'full-path\s*=\s*["\']([^"\']+)["\']', container, re.I)
    if not match:
        raise RuntimeError("EPUB container.xml 中没有 rootfile")
    return match.group(1)


def data_uri_for(zf: zipfile.ZipFile, base_dir: str, href: str) -> str | None:
    if not href or href.startswith(("data:", "http:", "https:", "//", "#")):
        return None
    parsed = urlparse(href)
    if parsed.scheme and parsed.scheme not in ("file",):
        return None
    rel = unquote(parsed.path)
    if not rel:
        return None
    candidate = os.path.normpath(os.path.join(base_dir, rel)).replace(os.sep, "/")
    try:
        data = zf.read(candidate)
    except KeyError:
        return None
    mime = mimetypes.guess_type(candidate)[0] or "application/octet-stream"
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


def rewrite_resources(fragment: str, zf: zipfile.ZipFile, base_dir: str) -> str:
    fragment = re.sub(r"<script\b[^>]*>.*?</script>", "", fragment, flags=re.I | re.S)
    fragment = re.sub(r"<script\b[^>]*/>", "", fragment, flags=re.I)

    def repl(match: re.Match[str]) -> str:
        tag = match.group(0)
        for name in ("src", "href", "xlink:href"):
            value = attr(tag, name)
            if not value:
                continue
            uri = data_uri_for(zf, base_dir, value)
            if uri:
                return re.sub(
                    rf'(\b{re.escape(name)}\s*=\s*)["\'][^"\']*["\']',
                    lambda m: f'{m.group(1)}"{uri}"',
                    tag,
                    count=1,
                    flags=re.I,
                )
        return tag

    return re.sub(r"<(?:img|image)\b[^>]*>", repl, fragment, flags=re.I)


def convert(epub_path: str, pdf_path: str) -> None:
    epub = Path(epub_path)
    if not epub.is_file():
        raise RuntimeError(f"EPUB 不存在: {epub}")
    with zipfile.ZipFile(epub) as zf:
        opf_path = find_opf(zf)
        opf = zf.read(opf_path).decode("utf-8", "replace")
        base_dir = os.path.dirname(opf_path)
        manifest: dict[str, tuple[str, str]] = {}
        for tag in re.findall(r"<item\b[^>]*>", opf, re.I):
            item_id = attr(tag, "id")
            href = attr(tag, "href")
            media = attr(tag, "media-type") or ""
            if item_id and href:
                manifest[item_id] = (href, media)
        spine_ids = [
            m.group(1)
            for m in re.finditer(r"<itemref\b[^>]*\bid\s*=\s*[\"']([^\"']+)[\"'][^>]*>", opf, re.I)
        ]
        if not spine_ids:
            spine_ids = [item_id for item_id, (_, media) in manifest.items()
                         if "html" in media]
        chapters: list[str] = []
        for item_id in spine_ids:
            item = manifest.get(item_id)
            if not item:
                continue
            href, media = item
            if "html" not in media and not href.lower().endswith((".xhtml", ".html", ".htm")):
                continue
            path = os.path.normpath(os.path.join(base_dir, unquote(urlparse(href).path)))
            path = path.replace(os.sep, "/")
            try:
                raw = zf.read(path).decode("utf-8", "replace")
            except KeyError:
                continue
            body = re.search(r"<body\b[^>]*>(.*?)</body>", raw, re.I | re.S)
            fragment = body.group(1) if body else raw
            fragment = rewrite_resources(fragment, zf, os.path.dirname(path))
            chapters.append(f'<section class="chapter">{fragment}</section>')
        if not chapters:
            raise RuntimeError("EPUB 中没有可渲染的 XHTML 章节")

    document = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<style>
  @page { size: A4; margin: 20mm 18mm; }
  html, body { margin: 0; padding: 0; background: #fffdf7; color: #222; }
  body { font-family: "Noto Serif CJK SC", "Source Han Serif SC", serif;
         font-size: 16px; line-height: 1.65; }
  .chapter { page-break-before: always; }
  .chapter:first-child { page-break-before: auto; }
  img, svg { max-width: 100%; height: auto; }
  h1, h2, h3, h4 { line-height: 1.3; page-break-after: avoid; }
  pre, code { white-space: pre-wrap; word-break: break-word; }
  table { border-collapse: collapse; max-width: 100%; }
  td, th { border: 1px solid #bbb; padding: 4px 6px; }
  a { color: #275d8c; }
</style></head><body>""" + "\n".join(chapters) + "</body></html>"
    temp_dir = tempfile.mkdtemp(prefix="meowo-epub-")
    html_path = os.path.join(temp_dir, "book.html")
    try:
        Path(html_path).write_text(document, encoding="utf-8")
        chrome = os.environ.get("MEOWO_CHROME") or shutil.which("google-chrome") \
            or shutil.which("chromium") or shutil.which("chromium-browser")
        if not chrome:
            raise RuntimeError("找不到 Google Chrome/Chromium，无法生成 EPUB 固定页快照")
        command = [
            chrome,
            "--headless",
            "--no-sandbox",
            "--disable-gpu",
            "--no-pdf-header-footer",
            "--virtual-time-budget=4000",
            f"--print-to-pdf={pdf_path}",
            Path(html_path).as_uri(),
        ]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=120)
        if result.returncode != 0 or not Path(pdf_path).is_file():
            raise RuntimeError("Chrome 生成 PDF 失败: " + result.stdout[-800:])
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: epub_to_pdf.py <input.epub> <output.pdf>", file=sys.stderr)
        return 2
    try:
        convert(sys.argv[1], sys.argv[2])
        return 0
    except Exception as exc:  # noqa: BLE001 - CLI boundary
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
