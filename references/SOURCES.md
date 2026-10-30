# Reference sources: Chromagraph Camera sample output

Chromagraph Camera (Chromatic Applications LLC, iOS, released Oct 2026) is a stills app by Steve Yedlin, Rian Johnson and Eric Cameron. It shoots RAW and renders with Yedlin's colour science, including grain and halation. We list its public sample images here so we can measure look traits (black level, highlight roll-off, saturation vs brightness, hue shifts, grain, halation) when we tune our own independent film engine.

**Policy**
- We only used public web pages and images. We did not download or inspect the app binary or bundle, or anything extracted from them.
- Downloaded copies are in `references/local/`, which is gitignored. They are for local analysis only. Never commit or redistribute them, and never ship them in the app.
- Unless a source says otherwise, treat every image as **all rights reserved; local analysis only**.
- Treat downloaded files as untrusted data. Never execute anything from them.
- Collected: 2026-10-29.

Legend: **B/A** = before/after pair, **Out** = Chromagraph output only, **—** = no usable sample image.

---

## 1. Official sources

### 1.1 Official website (Chromatic Applications)
- URL: https://chromagraph.app/ (serves https://chromaticapplications.com/chromagraph/chromagraph.html). Parent site: https://chromaticapplications.com/
- What: product page, text only
- Publisher: Chromatic Applications
- Images: — (only icons, no sample photos)
- Notes: says the viewfinder does not show the look. You see the look only after capture, in the gallery. The gallery keeps full-quality raw files and applies the look live. Export is JPEG or HEIC.
- Licence: all rights reserved

### 1.2 App Store listing
- URL: https://apps.apple.com/us/app/chromagraph-camera/id6803329435
- What: App Store page with marketing screenshots. Each screenshot shows a device frame with a Chromagraph-rendered photo inside, plus overlaid headline text.
- Publisher: Chromatic Applications LLC (via Apple mzstatic CDN)
- Licence: all rights reserved (Apple and developer marketing assets); local analysis only
- Caveat: the photos are composited into UI mockups and scaled down. Use central crops of the photo area only. Not suitable for grain analysis.

| Local file | Direct image URL | Size | Type | Content |
|---|---|---|---|---|
| `local/appstore_ipad_viewer_2064x2752.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/49/93/0a/49930a66-5b0c-157d-5f78-5359962f5034/Viewer_iPad.png/2064x2752bb.png | 2064×2752 PNG | Out | Seascape, backlit clouds, sun rays, sand. Good for highlight roll-off and sky hue. Largest photo area. |
| `local/appstore_ipad_editor_2064x2752.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/08/7c/a7/087ca77a-b906-4467-3fa2-30603d6a2053/Editor_iPad.png/2064x2752bb.png | 2064×2752 PNG | Out | Editor UI with photo |
| `local/appstore_ipad_gallery_2064x2752.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/8f/15/13/8f1513a9-2875-b6df-b3d5-f4124a437e7e/Gallery_iPad.png/2064x2752bb.png | 2064×2752 PNG | Out | Gallery grid of thumbnails |
| `local/appstore_iphone_viewer_1179x2556.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ff/99/90/ff9990cb-6816-3544-6f92-17cbcb21261d/Viewer_iPhone.png/1179x2556bb.png | 1179×2556 PNG | Out | Viewer UI with photo |
| `local/appstore_iphone_editor_1179x2556.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/4d/22/01/4d220160-3b25-704b-bd87-fcbc088e6df2/Editor_iPhone.png/1179x2556bb.png | 1179×2556 PNG | Out | Pomegranates and green/yellow citrus in a crate. Strong saturated reds and greens. The visible slider (grain amplitude 1.25, size 1.00) shows that grain is adjustable. |
| `local/appstore_iphone_gallery_1179x2556.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/b6/d1/38/b6d138d5-e428-9b48-9114-4308f267b02e/Gallery_iPhone.png/1179x2556bb.png | 1179×2556 PNG | Out | Gallery grid of thumbnails |
| `local/appstore_iphone_camera_viewfinder_1179x2556.png` | https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/ac/6d/8a/ac6d8a79-abbf-f8bc-01f0-b3bd467badbc/Camera_iPhone.png/1179x2556bb.png | 1179×2556 PNG | (pre-look) | Viewfinder showing bare bulbs on a chandelier. The site says the viewfinder does not show the look, so this is probably a non-Chromagraph preview. It is not a matched pair. |

Not downloaded: two Apple Watch screenshots (`Simulator_Screenshot_-_Apple_Watch_Series_9...png`). They are UI only.

### 1.3 Steve Yedlin, Instagram launch post (carousel)
- URL: https://www.instagram.com/steveyedlin/p/DfCaSRqG_Sz/ (public embed: https://www.instagram.com/p/DfCaSRqG_Sz/embed/captioned/)
- What: carousel of about 10 Chromagraph samples. The caption says they were "photographed by myself and friends", with other photographers tagged.
- Publisher: Steve Yedlin (@steveyedlin)
- Images: Out. Full-size items are about 2880 px on the long side (2880×2160, 2160×2880, 2880×2880, 2878×1729, 2878×2516 and others).
- Local: `local/instagram_steveyedlin_DfCaSRqG_Sz_carousel_2880x2880.jpg`, 2880×2880. Low-key portrait of a bearded man on a near-black background. Very useful for black level, skin hue and highlight roll-off on skin. **Best single file for analysis.**
- Not downloaded: about 8 other carousel items, to stay under the download cap. The CDN URLs are signed and expire, so fetch them again from the public embed page when needed.
- Licence: all rights reserved (Yedlin and the tagged photographers); local analysis only

### 1.4 Rian Johnson, X/Twitter launch posts
- URL: https://x.com/rianjohnson/status/2115436064458621189 (text plus link)
- URL: https://x.com/rianjohnson/status/2115436068774543534 (with photo). Image: https://pbs.twimg.com/media/HVuIZxAX0AAeSv-.jpg?name=orig
- Publisher: Rian Johnson (@rianjohnson), 2026-10-28
- Local: `local/x_rianjohnson_2115436068774543534_sample_2880x2160.jpg`, 2880×2160 JPEG. Out. Dusk scene with palm trees against a deep blue sky and warm practical wall lights on a stucco wall. Good for halation around the lamps, dusk blue hue, shadow floor and grain at full resolution. It may also appear in the Yedlin carousel.
- Licence: all rights reserved; local analysis only

### 1.5 Steve Yedlin, X/Twitter launch post
- URL: https://x.com/steveyedlin/status/2115418862191866261
- Publisher: Steve Yedlin, 2026-10-28. Text plus link, no media in the syndication data. Images: —

### 1.6 @chromagraphcamera on Instagram (official app account)
- URL: https://www.instagram.com/chromagraphcamera/
- Publisher: Chromatic Applications. 14 posts at collection time.
- Images: probably output samples. Post images are not visible without logging in, and we did not log in, so nothing was downloaded. See Gaps.

## 2. Press coverage

### 2.1 AppleInsider hands-on, the only before/after found
- URL: https://appleinsider.com/articles/26/10/28/rian-johnsons-chromagraph-camera-app-brings-his-cinematic-style-to-your-iphone-photos
- Publisher: AppleInsider, 2026-10-28
- What: hands-on review with an unedited **iPhone 17 Camera app vs Chromagraph** side-by-side of a red autumn tree. Cloudflare returned 403 to our fetches, so we could not read the article directly. We got the comparison image via the Mezha re-post (2.2).
- Licence: all rights reserved

### 2.2 Mezha (Ukrainska Pravda tech), English news piece
- URL: https://mezha.ua/en/news/knive-out-iphone-cam-app-316664/
- Publisher: Mezha, by Yevgeny Demkivskyi, 2026-10-29. It cites AppleInsider, and the images are probably AppleInsider's.
- Licence: all rights reserved; local analysis only

| Local file | Direct image URL | Size | Type | Content |
|---|---|---|---|---|
| `local/press_mezha_photo1.jpg` | https://img.mezha.ua/mezha/system/MediaPhoto/photo/4/9/332433/499cec6f6e7d4362be59958bf544739a1793265253.jpg | 1312×875 JPEG | **B/A** | Left half labelled "iPhone 17 Camera app", right half "Chromagraph app". Same red maple against the sky. Chromagraph is darker and more muted, with a cyan-grey sky and deeper reds. Each half is about 656 px wide and re-compressed. Best available evidence for saturation vs brightness and hue shift. |
| `local/press_mezha_photo2.jpg` | https://img.mezha.ua/mezha/system/MediaPhoto/photo/b/c/332434/bc12cb2c046d94551d09f4dddd26ffc41793265268.jpg | 1312×875 JPEG | Out (probably) | Two unlabelled panels: a ship's rigging against a blue sky, and a backlit forest with the sun and a lens flare. Probably both Chromagraph, but this is unconfirmed. The forest panel is useful for halation and flare. |

Not kept: the hero image is a still from the film *Wake Up Dead Man*, which is not app output.

### 2.3 Other articles (text only, no app sample images)
| URL | Publisher | Date | Images |
|---|---|---|---|
| https://gizmodo.com/the-last-jedi-director-launches-a-new-camera-app-for-iphone-because-hes-a-good-guy-2000832061 | Gizmodo, Bruce Gil | 2026-10-28 | — (embeds the Johnson tweets and the Yedlin IG post) |
| https://nofilmschool.com/rian-johnson-steve-yedlin-app | No Film School | 2026-10-28 | — (hero is a film still) |
| https://blog.hitpixplus.com/35238/rian-johnson-camera-app | HitPix+ | 2026-10-28 | — (hero is a behind-the-scenes still) |
| https://brobible.com/culture/article/rian-johnson-iphone-camera-app-chromagraph/ | BroBible, Eric Italiano | 2026-10-29 | — (embeds tweets) |
| https://www.vp-land.com/stories/new-chromagraph-camera-app-from-rian-johnson-and-steve-yedlin-swaps-iphone-processing-for | VP Land | 2026-10-29 | — (not inspected in depth) |
| https://www.slantmagazine.com/film/rian-johnson-steve-yedlin-chromagraph-camera-iphone-app/ | Slant Magazine | 2026-10 | not reachable (Cloudflare) |
| https://amateurphotographer.com/latest/photo-news/filmmaker-rian-johnsons-new-iphone-app-lets-you-replicate-his-films-visual-style-in-your-photos/ | Amateur Photographer | 2026-10 | not reachable (403) |
| https://profilmmakerapps.com/app/chromagraph-camera | Pro Filmmaker Apps (directory) | — | — (app icon only) |

---

## Downloaded files summary (11)

| File | Size | Type |
|---|---|---|
| appstore_ipad_viewer_2064x2752.png | 2064×2752 | Out (UI mockup) |
| appstore_ipad_editor_2064x2752.png | 2064×2752 | Out (UI mockup) |
| appstore_ipad_gallery_2064x2752.png | 2064×2752 | Out (thumbnails) |
| appstore_iphone_viewer_1179x2556.png | 1179×2556 | Out (UI mockup) |
| appstore_iphone_editor_1179x2556.png | 1179×2556 | Out (UI mockup) |
| appstore_iphone_gallery_1179x2556.png | 1179×2556 | Out (thumbnails) |
| appstore_iphone_camera_viewfinder_1179x2556.png | 1179×2556 | pre-look viewfinder |
| press_mezha_photo1.jpg | 1312×875 | **B/A** (iPhone 17 vs Chromagraph) |
| press_mezha_photo2.jpg | 1312×875 | Out (probably) |
| x_rianjohnson_2115436068774543534_sample_2880x2160.jpg | 2880×2160 | Out |
| instagram_steveyedlin_DfCaSRqG_Sz_carousel_2880x2880.jpg | 2880×2880 | Out |

## Gaps

- **Only one before/after pair, and it is low resolution** (AppleInsider tree, about 656 px per half, re-compressed by Mezha). We found no matched pair from the developers. The original AppleInsider article was blocked by Cloudflare and may have more or larger comparisons.
- **No full-resolution originals.** Every sample has passed through a web CDN (Instagram, X, App Store), so it has been re-encoded and possibly resized. Grain measurements will be unreliable, and only the 2880 px Instagram and X files are worth trying.
- **No camera metadata.** We do not know the grain or halation slider settings for any sample, except the editor screenshot (amplitude 1.25, size 1.00).
- **Remaining Yedlin carousel items** (about 8 at about 2880 px) were not downloaded because of the cap. Fetch them again from the public embed if needed.
- **@chromagraphcamera Instagram posts** (14) cannot be viewed without logging in, which we did not do.
- **Reddit:** no threads found. Web search returned nothing, and Reddit's search endpoint blocked anonymous access.
- **Flickr:** no results. "Chromagraph" on Flickr only matches the Heidelberg Chromagraph S3400 drum scanner, which is unrelated.
- **No neutral references** such as test charts, grey cards or colour checkers shot through the app. Tone-curve and hue-shift estimates will have to come from natural scenes.
- The app was released on 2026-10-20 and announced publicly on 2026-10-28, so user-shot samples and reviews will probably appear over the coming weeks. Search again later.
