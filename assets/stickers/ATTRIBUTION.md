# Sticker artwork — attribution and licences

Wings ships a fixed, local sticker catalogue. No sticker is downloaded at
runtime, stored in Firestore, or fetched from a third-party host. The catalogue
is described by `sticker_manifest.json`; ids in that file are what comments store.

## OpenMoji — `assets/stickers/openmoji/`

- Source: <https://github.com/hfg-gmuend/openmoji>
- Authors: OpenMoji project (HfG Schwäbisch Gmünd)
- Licence: **CC BY-SA 4.0** — <https://creativecommons.org/licenses/by-sa/4.0/>
- Changes: the original 618×618 PNG graphics were resized to 256×256 WebP
  (lossy quality 92) and renamed to `om_<codepoint>.webp` so the file name and the
  stable sticker id match.

The OpenMoji graphics remain under CC BY-SA 4.0, including the resized copies
distributed inside this app. Attribution is given here and the share-alike term
applies to those graphics.

## Wings chibi set — `assets/stickers/chibi/`

- Source: artwork created for Wings for this feature; no third-party character,
  franchise, screenshot or sticker pack was used.
- Licence: Wings original artwork, distributed with the app.
- Files: `cb_laugh`, `cb_cry`, `cb_angry`, `cb_shock`, `cb_love`, `cb_sleep`,
  `cb_thumbs`, `cb_party` (512×512 WebP, transparent background).

## Maintenance rules

- Never change an existing `stickerId`; `enabled: false` retires a sticker
  without breaking comments that already reference it.
- Only add artwork whose licence allows redistribution inside the app, and
  record the source and licence in `sticker_manifest.json` and in this file.
