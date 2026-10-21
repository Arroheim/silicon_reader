# Local patches to djvudec

Vendored from https://github.com/kjk/djvudec `dist/djvu.c` + `dist/djvu.h`,
commit `cfd3251835b2abcc110d0cde479a7b3143e2892d` (2026-08-11).
Re-apply these after updating the files from upstream, or drop them once
upstream has the fix.

## 0001 — long INCL component ids were truncated

**Symptom:** some pages of multi-page DjVu files fail to render ("JB2: decode
failed"), always in ranges of pages that share a JB2 shape dictionary.

**Cause:** an `INCL` chunk names the component holding the shared dictionary
(`Djbz`). djvudec copied that name into `char id[64]`, cutting it to 63 bytes.
Component names are file names; with Cyrillic titles (2 bytes per letter in
UTF-8) they easily exceed that, so the dictionary lookup failed and every page
using it could not be decoded. Found by `make check-library` on a real library:
5 of 82 DjVu books affected (INCL ids of 90 and 115 bytes).

**Fix:** the three `char id[64]` buffers that hold INCL ids are 1024 bytes
(marked `silicon-reader patch 0001` in `djvu.c`).

**Upstream:** not reported yet.
