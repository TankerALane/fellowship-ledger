# Fellowship Ledger brand assets

Original artwork: a compass rose with an hourglass at its center. It uses generic shapes only, with no Blizzard logos, characters or trademarks.

## Palette

| Name | Hex | Use |
|---|---|---|
| Ink | `#3B2A1A` | Text and line work on parchment |
| Parchment | `#F1E4C3` | Window and page background |
| Gold | `#C99A2E` | Rings, star, accents (graphics only, not body text) |
| Light gold | `#E0B34A` | Gold on dark backgrounds |
| Dark gold | `#7A560F` | Gold-colored text on parchment (passes 4.5:1 contrast) |
| Night | `#2B1E12` | Icon tile and dark background |
| Glass | `#F6EBD0` | Hourglass glass fill |

Fonts used in the logo: Cinzel (wordmark) and Crimson Pro italic (tagline). Both are free (SIL Open Font License). The in-game UI can use Blizzard's built-in fonts.

## Files

| File | What it is |
|---|---|
| `logo/mark-light.svg` | Mark on a transparent background, for light or parchment backgrounds |
| `logo/mark-dark.svg` | Mark on a transparent background, for dark backgrounds |
| `logo/icon-tile.svg` | Square dark icon, 512x512, for CurseForge and GitHub avatars |
| `logo/minimap-icon.svg` | Round dark icon for the minimap button |
| `logo/lockup.svg` | Full logo with wordmark and tagline. Text is live, so install Cinzel and Crimson Pro to match exactly, or export from the design canvas |
| `logo/png/icon-{512,256,128,64}.png` | Raster versions of the square icon |
| `logo/png/mark-{light,dark}-512.png` | Raster versions of the transparent marks |
| `logo/png/minimap-icon-{64,256}.png` | Raster versions of the round icon |
| `../FellowshipLedger/media/icon.tga` | In-game addon list icon, 128x128, 32-bit uncompressed TGA |
| `../FellowshipLedger/media/minimap-icon.tga` | Minimap button texture, 64x64, 32-bit uncompressed TGA with transparent corners |

Source of truth for the lockup is the "Fellowship Ledger Logo" design canvas in Claude.

## Notes

- TGA files are power-of-two sizes, which the game expects. If the game ever refuses one, convert to BLP.
- Do not add Blizzard artwork, logos or character art to this project. Describe it as "for World of Warcraft" in text only.
