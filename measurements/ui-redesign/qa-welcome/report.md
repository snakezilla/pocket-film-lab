# QA report: http://127.0.0.1:4319/

Engine: playwright. Captured 2026-10-30 12:02.

| Frame | Checks | Notes |
|---|---|---|
| 320 light | img-size 1, contrast 1, meta 4 |  |
| 320 dark | img-size 1, meta 4 |  |
| 390 light | img-size 1, contrast 1, meta 4 |  |
| 390 dark | img-size 1, meta 4 |  |
| 768 light | img-size 1, contrast 1, meta 4 |  |
| 768 dark | img-size 1, meta 4 |  |
| 1024 light | img-size 1, contrast 1, meta 4 |  |
| 1024 dark | img-size 1, meta 4 |  |
| 1440 light | img-size 1, contrast 1, meta 4 |  |
| 1440 dark | img-size 1, meta 4 |  |
| 390 light reduced-motion | img-size 1, contrast 1, meta 4 |  |
| 390 light no-webfonts | img-size 1, contrast 1, meta 4 |  |
| 390 light no-js | clean |  |

## Findings

- [320 light] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [320 light] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [320 light] meta: no <meta name="description">; link previews will show nothing or random body text
- [320 light] meta: no og:title; chat apps fall back to a bare link
- [320 light] meta: no og:image; the preview card will have no picture
- [320 light] meta: no favicon link
- [320 dark] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [320 dark] meta: no <meta name="description">; link previews will show nothing or random body text
- [320 dark] meta: no og:title; chat apps fall back to a bare link
- [320 dark] meta: no og:image; the preview card will have no picture
- [320 dark] meta: no favicon link
- [390 light] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [390 light] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [390 light] meta: no <meta name="description">; link previews will show nothing or random body text
- [390 light] meta: no og:title; chat apps fall back to a bare link
- [390 light] meta: no og:image; the preview card will have no picture
- [390 light] meta: no favicon link
- [390 dark] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [390 dark] meta: no <meta name="description">; link previews will show nothing or random body text
- [390 dark] meta: no og:title; chat apps fall back to a bare link
- [390 dark] meta: no og:image; the preview card will have no picture
- [390 dark] meta: no favicon link
- [768 light] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [768 light] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [768 light] meta: no <meta name="description">; link previews will show nothing or random body text
- [768 light] meta: no og:title; chat apps fall back to a bare link
- [768 light] meta: no og:image; the preview card will have no picture
- [768 light] meta: no favicon link
- [768 dark] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [768 dark] meta: no <meta name="description">; link previews will show nothing or random body text
- [768 dark] meta: no og:title; chat apps fall back to a bare link
- [768 dark] meta: no og:image; the preview card will have no picture
- [768 dark] meta: no favicon link
- [1024 light] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [1024 light] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [1024 light] meta: no <meta name="description">; link previews will show nothing or random body text
- [1024 light] meta: no og:title; chat apps fall back to a bare link
- [1024 light] meta: no og:image; the preview card will have no picture
- [1024 light] meta: no favicon link
- [1024 dark] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [1024 dark] meta: no <meta name="description">; link previews will show nothing or random body text
- [1024 dark] meta: no og:title; chat apps fall back to a bare link
- [1024 dark] meta: no og:image; the preview card will have no picture
- [1024 dark] meta: no favicon link
- [1440 light] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [1440 light] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [1440 light] meta: no <meta name="description">; link previews will show nothing or random body text
- [1440 light] meta: no og:title; chat apps fall back to a bare link
- [1440 light] meta: no og:image; the preview card will have no picture
- [1440 light] meta: no favicon link
- [1440 dark] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [1440 dark] meta: no <meta name="description">; link previews will show nothing or random body text
- [1440 dark] meta: no og:title; chat apps fall back to a bare link
- [1440 dark] meta: no og:image; the preview card will have no picture
- [1440 dark] meta: no favicon link
- [390 light reduced-motion] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [390 light reduced-motion] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [390 light reduced-motion] meta: no <meta name="description">; link previews will show nothing or random body text
- [390 light reduced-motion] meta: no og:title; chat apps fall back to a bare link
- [390 light reduced-motion] meta: no og:image; the preview card will have no picture
- [390 light reduced-motion] meta: no favicon link
- [390 light no-webfonts] img-size: no width/height attributes, layout will shift when it loads at `img#view`
- [390 light no-webfonts] contrast: #ffffff on #c25e22 small: 4.27:1 (needs 4.5:1), 1 element(s), smallest 17px, e.g. at `button#pick.btn.btn-primary "Choose Photos"`
- [390 light no-webfonts] meta: no <meta name="description">; link previews will show nothing or random body text
- [390 light no-webfonts] meta: no og:title; chat apps fall back to a bare link
- [390 light no-webfonts] meta: no og:image; the preview card will have no picture
- [390 light no-webfonts] meta: no favicon link

Read contact-sheet.png frame by frame before calling this clean.
