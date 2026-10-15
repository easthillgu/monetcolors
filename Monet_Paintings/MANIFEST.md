# Monet_Paintings — Source Inventory

High-resolution reference paintings used to derive the Monet color baseline
(`MonetColorBaseline.lua` v3, `monet_palette_v3.json`, `monet_red_domain_v3.json`).

The JPEG binaries themselves are **not committed** (see `.gitignore`); this
manifest records what they are and how to get them back.

- **Source**: Wikimedia Commons, public domain (Claude Monet, d. 1926)
- **Captured**: 2026-10-12, downloaded at maximum available resolution
- **Extraction**: 100xN sampling, step=16, L filter 0.08-0.94

> The exact Commons *file pages* were not recorded during the original capture,
> so instead of guessed URLs each row links to a Commons media search for that
> painting. Pick the highest-resolution public-domain scan and verify the
> SHA-256 below before trusting the derived data.

## Inventory

| File | Painting | Pixels (WxH) | Bytes | Commons search |
| :--- | :--- | :--- | ---: | :--- |
| Bridge_over_a_Pond_of_Water_Lilies.jpg | Bridge over a Pond of Water Lilies | 2966x3722 | 4882352 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Bridge%20over%20a%20Pond%20of%20Water%20Lilies%20Monet) |
| Camille_Monet_in_the_Garden.jpg | Camille Monet in the Garden | 2758x3722 | 4679940 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Camille%20Monet%20in%20the%20Garden) |
| Camille_Monet_on_a_Garden_Bench.jpg | Camille Monet on a Garden Bench | 1905x1441 | 2432440 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Camille%20Monet%20on%20a%20Garden%20Bench) |
| Garden_at_Sainte-Adresse.jpg | Garden at Sainte-Adresse | 3811x2878 | 2988289 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Garden%20at%20Sainte-Adresse%20Monet) |
| Grainstacks.jpg | Grainstacks | 3811x2711 | 3342264 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Grainstacks%20Monet) |
| Houses_on_the_Achterzaan.jpg | Houses on the Achterzaan | 3811x2506 | 2760327 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Houses%20on%20the%20Achterzaan%20Monet) |
| Jean_Monet_on_His_Horse_Tricycle.jpg | Jean Monet on His Horse Tricycle | 5737x4710 | 5770617 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Jean%20Monet%20on%20his%20horse%20tricycle) |
| Poppy_Field_1873.jpg | Poppy Field (1873) | 5586x4258 | 5220393 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Poppy%20Field%201873%20Monet) |
| Red_Boats_Argenteuil_1875.jpg | Red Boats, Argenteuil (1875) | 5208x3853 | 8547078 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Red%20Boats%20Argenteuil%20Monet) |
| Rouen_Cathedral_The_Portal_Sunlight.jpg | Rouen Cathedral, The Portal, Sunlight | 2464x3722 | 3657409 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Rouen%20Cathedral%20Portal%20Sunlight%20Monet) |
| The_Four_Trees.jpg | The Four Trees | 3689x3658 | 4178536 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=The%20Four%20Trees%20Monet) |
| The_Path_through_the_Irises.jpg | The Path through the Irises | 3324x3689 | 4524360 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=The%20Path%20through%20the%20Irises%20Monet) |
| View_of_Vetheuil.jpg | View of Vetheuil | 2820x3722 | 3717586 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=View%20of%20Vetheuil%20Monet) |
| Water_Lilies.jpg | Water Lilies | 3811x2486 | 3562360 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=Water%20Lilies%20Monet%201906) |
| Woman_in_Red_Dress_La_Japonaise.jpg | La Japonaise (Woman in a Red Dress) | 1440x2370 | 2671916 | [search](https://commons.wikimedia.org/w/index.php?title=Special:MediaSearch&type=image&search=La%20Japonaise%20Monet) |

## Integrity (SHA-256)

```
4187B3DB6DED1BD282F7DF1034B041B91599A19B2EA0F9C30955B3DFC4E51041  Bridge_over_a_Pond_of_Water_Lilies.jpg
9F02C872A98299FA87B62EA5C30C600EF40A1D01E0D447EA0C1597E1FFFC0EC2  Camille_Monet_in_the_Garden.jpg
F0B46BEBD02C6D90F5A2A406728A3425F3FFF960D94C2F00C1B1B077BBCDE294  Camille_Monet_on_a_Garden_Bench.jpg
C64EDBE971A72533C0CD478341EB200E659086C2880B3A85C0E4C65572D65B7C  Garden_at_Sainte-Adresse.jpg
BFF90FB6CE5D0A3B2C1C5F794EB54A732E98F1DC4F604B6F286E69E7588882A9  Grainstacks.jpg
DDE52ABA81DEC961267634D35CC2A2E5C064DBB6558674393877AE297BD8FC86  Houses_on_the_Achterzaan.jpg
D86395D0D4CC8E0B090295B2856E4BDDE9F03A697D4CB0C4CADD84C5045E1002  Jean_Monet_on_His_Horse_Tricycle.jpg
6DCBF8484919F516C05CEA4CBF61C3A20AE5631E521FC81A093D9436999F9E32  Poppy_Field_1873.jpg
DED23671817511F0CB1B47F7E2EB5BFFE471E87A79B1E7127F49153F268AE7A5  Red_Boats_Argenteuil_1875.jpg
95AA60CA1D80F9C2B26E9800864121F188FDF446B43C1B613A3AA515C56EC688  Rouen_Cathedral_The_Portal_Sunlight.jpg
30F99054FF4799B88B23108562C271D9C84F45C8BAB8B59EB924B34CBED332BB  The_Four_Trees.jpg
356EEF0152A8A58EBBC5AA825D8EDF4AE6421A9FCCB4B53BD6BE9A9716926028  The_Path_through_the_Irises.jpg
09D5C49DB4531DA0808B018D5BEFA0E31DF4B6D57BF4AB1F1BFAE44133D528A1  View_of_Vetheuil.jpg
E9A3BE830817C4D7F52DFEE606903BD35A076D125C0E8262A668EF9281A57A92  Water_Lilies.jpg
77E12963739FB1F9EA66B27B97BBBD131005C4E1E7ADC915DE2457CB364E5A55  Woman_in_Red_Dress_La_Japonaise.jpg
```

Verify with PowerShell:

```powershell
Get-ChildItem Monet_Paintings -Filter *.jpg |
  Get-FileHash -Algorithm SHA256 |
  Format-Table Hash, Path
```

## `_backup_lowres/`

Low-resolution copies kept on disk for quick visual comparison during
development. Ignored by git; not used by any extraction step.
