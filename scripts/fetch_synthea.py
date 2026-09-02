#!/usr/bin/env python3
"""Fetch the Synthea sample CSV dataset into data/raw/synthea/.

Downloads a pinned, checksummed zip of synthetic EHR data published by the
Synthea project (MITRE), verifies it, and extracts its CSV files. Re-running
is a no-op while every extracted file is present at its recorded size; pass
--force to fetch again. Needs about 600 MB free under data/raw/ (the CSVs
total 565 MB, 310 MB of it claims_transactions.csv), twice that with --force.

Standard library only, so it runs wherever the repo's Python does, CI included.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import shutil
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

DATASET = "synthea_sample_data_csv_nov2021"
URL = f"https://synthetichealth.github.io/synthea-sample-data/downloads/{DATASET}.zip"
SHA256 = "870b68a127f3570ca964e89e49dd3433cf3e7a27cc4079d2bff5f094be0a43c2"
MEMBER_PREFIX = "csv/"  # every CSV inside the archive sits under this folder
EXPECTED_FILES = 18

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data" / "raw"
DEST_DIR = DATA_DIR / "synthea"
WORK_DIR = DATA_DIR / ".synthea_download"  # scratch for one run; wiped at start and end
MANIFEST = DEST_DIR / ".fetched"  # archive sha256, then one "size<TAB>name" line per CSV


class FetchError(RuntimeError):
    """A fatal condition with a one-line message for the user."""


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, dest: Path, attempts: int = 3) -> None:
    """Stream url to dest, checking the byte count against Content-Length.

    Retries on network errors and short reads; a 4xx response is final.
    """
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        print(f"downloading {url} (attempt {attempt}/{attempts})", flush=True)
        try:
            with urllib.request.urlopen(url, timeout=60) as resp, dest.open("wb") as out:
                header = resp.headers.get("Content-Length")
                expected = int(header) if header else None
                received = 0
                for chunk in iter(lambda: resp.read(1 << 20), b""):
                    out.write(chunk)
                    received += len(chunk)
            if expected is not None and received != expected:
                raise FetchError(f"incomplete download: {received:,} of {expected:,} bytes")
            print(f"  {received:,} bytes", flush=True)
            return
        except urllib.error.HTTPError as err:
            if 400 <= err.code < 500:
                raise FetchError(f"HTTP {err.code} for {url}") from err
            last_error = err
        except (FetchError, OSError, http.client.HTTPException) as err:
            last_error = err
        print(f"  attempt {attempt} failed: {last_error}", flush=True)
        if attempt < attempts:
            time.sleep(2 * attempt)
    raise FetchError(f"giving up after {attempts} attempts: {last_error}")


def extract_csvs(archive: Path, dest_dir: Path) -> list[Path]:
    written: list[Path] = []
    with zipfile.ZipFile(archive) as zf:
        members = [
            m
            for m in zf.infolist()
            if not m.is_dir()
            and m.filename.startswith(MEMBER_PREFIX)
            and m.filename.endswith(".csv")
        ]
        if len(members) != EXPECTED_FILES:
            raise FetchError(
                f"expected {EXPECTED_FILES} {MEMBER_PREFIX}*.csv members in "
                f"{archive.name}, found {len(members)}; the archive layout changed"
            )
        for m in members:
            target = dest_dir / Path(m.filename).name  # flatten; no path traversal
            with zf.open(m) as src, target.open("wb") as out:
                shutil.copyfileobj(src, out)
            written.append(target)
    return written


def manifest_text(files: list[Path]) -> str:
    return SHA256 + "\n" + "".join(f"{f.stat().st_size}\t{f.name}\n" for f in sorted(files))


def already_fetched() -> bool:
    """True only if the manifest matches this pin and every file is present at its recorded size."""
    if not MANIFEST.exists():
        return False
    lines = MANIFEST.read_text().splitlines()
    if len(lines) < 2 or lines[0] != SHA256:
        return False
    for line in lines[1:]:
        size, _, name = line.partition("\t")
        f = DEST_DIR / name
        if not size.isdigit() or not f.is_file() or f.stat().st_size != int(size):
            return False
    return True


def fetch() -> list[Path]:
    """Download, verify, and extract into WORK_DIR, then swap into DEST_DIR.

    DEST_DIR is only replaced once a complete, verified set of files exists,
    so a failed run leaves whatever was there before untouched.
    """
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(WORK_DIR, ignore_errors=True)  # debris from an interrupted run
    WORK_DIR.mkdir()
    try:
        archive = WORK_DIR / f"{DATASET}.zip"
        download(URL, archive)
        actual = sha256_of(archive)
        if actual != SHA256:
            raise FetchError(
                f"sha256 mismatch for {archive.name}: the published archive differs "
                f"from the pinned one\n  expected {SHA256}\n  actual   {actual}"
            )
        staged = WORK_DIR / "csv"
        staged.mkdir()
        extract_csvs(archive, staged)
        archive.unlink()  # free the 59 MB before the swap
        if DEST_DIR.exists():
            shutil.rmtree(DEST_DIR)
        staged.rename(DEST_DIR)
    finally:
        shutil.rmtree(WORK_DIR, ignore_errors=True)
    files = sorted(DEST_DIR.glob("*.csv"))
    MANIFEST.write_text(manifest_text(files))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--force", action="store_true", help="fetch and extract again even if present"
    )
    args = parser.parse_args()

    if already_fetched() and not args.force:
        print(f"already fetched: {DEST_DIR.relative_to(REPO_ROOT)} (sha256 {SHA256[:12]}...)")
        return 0
    try:
        files = fetch()
    except FetchError as err:
        print(f"error: {err}", file=sys.stderr, flush=True)
        return 1
    for f in files:
        print(f"  {f.stat().st_size:>12,}  {f.relative_to(REPO_ROOT)}")
    print(f"extracted {len(files)} files to {DEST_DIR.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
