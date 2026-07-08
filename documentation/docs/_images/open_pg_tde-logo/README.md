# open_pg_tde — Logo & Brand Assets

Identity for **`open_pg_tde`**, Transparent Data Encryption for native PostgreSQL —
an open fork of Percona `pg_tde`, maintained by Command Prompt, Inc.

## The mark

The **Sealed Stack**: a PostgreSQL database cylinder with a keyhole cut into its
face. It says the two things the project is about at a glance — *data at rest*
(the disk stack) and *encryption* (the keyhole). The keyhole is carried in warm
amber: the protected secret is the valuable thing. The disk seam under the lid
reappears as the amber underline in the wordmark, the one recurring "seam" motif
that ties mark and type together.

The wordmark is set in **IBM Plex Mono** — a nod to the `open_pg_tde` identifier
itself and to Command Prompt. The tagline uses **IBM Plex Sans**.

All SVGs are self-contained: text is converted to outlines, so they render
identically with or without the fonts installed.

## Files

```
mark/            The icon on its own
  icon-color.svg           primary, works on light or dark
  icon-black.svg           single-colour (ink) for light backgrounds
  icon-white.svg           single-colour (white) for dark backgrounds
  icon-on-paper.svg        colour mark on the paper background tile
  icon-on-ink.svg          colour mark on the ink background tile
  icon-on-blue.svg         white mark on the PostgreSQL-blue tile

horizontal/      Mark + wordmark, side by side (README headers, nav bars)
  horizontal-color.svg / -on-ink.svg / -black.svg / -white.svg

stacked/         Mark above wordmark + tagline (splash, docs, slides)
  stacked-color.svg / -on-ink.svg / -black.svg / -white.svg

wordmark/        Type only
  wordmark-color.svg / -black.svg / -white.svg

favicon/         Bolder, simplified tile for small sizes
  favicon.svg, favicon.ico, favicon-16/32/48/64/192/512.png,
  apple-touch-icon.png

png/             Raster exports of the mark and horizontal lockup
  open_pg_tde-mark-64/128/256/512/1024.png (transparent)
  open_pg_tde-mark-white-256/512.png
  open_pg_tde-horizontal-1600.png, -on-ink-1600.png

social/          Open Graph / repo social preview (1280×640)
  open_graph.svg, open_graph.png

fonts/           IBM Plex Mono + Sans (OFL) used in the wordmark & tagline
```

## Colour

| Token        | Hex       | Use                                   |
|--------------|-----------|---------------------------------------|
| PG Blue      | `#2F6D9E` | Primary — the cylinder body           |
| PG Blue Dk   | `#234F73` | Rims, seams, depth                    |
| PG Blue Lt   | `#5C95C0` | The lid disk                          |
| Cipher Amber | `#EAA23C` | Accent — the keyhole and the seam line|
| Amber Dk     | `#CF8420` | Amber shadow / hover                  |
| Ink          | `#16232B` | Text on light, dark backgrounds       |
| Paper        | `#F6F3EC` | Warm light background                 |
| Mist         | `#DCE6EC` | Light blue-grey surfaces / dividers   |

## Typography

- **Wordmark / code:** IBM Plex Mono, SemiBold.
- **Tagline / UI:** IBM Plex Sans, Medium / SemiBold.
- Both are SIL Open Font License; the files ship in `fonts/`.

## Clear space & minimum size

- **Clear space:** keep free space around the lockup equal to the height of the
  keyhole (roughly the cap height of the wordmark) on all sides.
- **Minimum sizes:** mark no smaller than **24 px**; below that use
  `favicon/` (built to stay legible down to 16 px). Horizontal lockup no
  narrower than **160 px**.

## Favicon usage

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

## Do / Don't

- **Do** use `-on-ink` / `-white` variants on dark backgrounds; keep the colour
  mark on light or dark, never on a mid-tone that fights the blue.
- **Do** preserve the mark's proportions — scale uniformly.
- **Don't** recolour the keyhole, rotate the mark, add effects, or set the
  wordmark in a different typeface.
- **Don't** place the colour mark on a background close to `#2F6D9E`; use a
  single-colour variant instead.

## Licensing

Logo and wordmark © Command Prompt, Inc. IBM Plex is © IBM Corp., licensed under
the SIL Open Font License 1.1 (see `fonts/OFL.txt`).
