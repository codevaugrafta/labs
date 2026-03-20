# Bundled audio — licenses

## `community-adhan-wikimedia.m4a`

- **Source**: Wikimedia Commons — [File:Azan.ogg](https://commons.wikimedia.org/wiki/File:Azan.ogg) (MP3 transcode used as intermediate for AAC encoding).
- **Author**: Andrewler (own work, uploaded 2022-09-03).
- **License**: [Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)](https://creativecommons.org/licenses/by-sa/4.0/).
- **Your obligations when redistributing**: give appropriate credit, link to the license, indicate if changes were made (format conversion to AAC counts as a change — this file is a transcode). If you remix further, use a compatible license.

## `gentle-chime.m4a`

- **Source**: Short sine tone generated for this project (no third-party recording). Reproducible via `Adhan/scripts/generate-gentle-chime.sh` (Python `wave` + `afconvert`).
- **License**: treated as project-original; safe to ship with the app.

## Integrity

After download, the upstream MP3 was checked with `file(1)` (audio container, not Mach-O) and converted with `afconvert` only. Do not replace these files with executables or untrusted downloads.
