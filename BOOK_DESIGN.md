# Book designs

On the shelf, long-press a book on mobile, or use its context menu on desktop, and choose **Customize cover**. The dialog previews a draft and saves only when Save is pressed. Choose one of five presets: Basic, Medieval, Minecraft, Diary, and Pixelated. Choosing a preset resets its icon, border, texture, bookmark and color; title, subtitle and author remain. The color, icon, border, texture and decorative bookmark can then be adjusted independently. The Minecraft design is original, programmatically drawn grass, dirt and a quill; it does not bundle game assets.

Artwork is selected through the existing platform picker and copied using the existing book-cover import. An image replaces the generated cover; choose **Use generated cover** to remove the image reference. The original selected file is not deleted. Existing image covers remain unchanged until explicitly replaced or removed. The subtitle and author are cover text, separate from the existing subject and reader page text. The bookmark is decorative, not a navigational page marker.

If a referenced image cannot be loaded, the generated cover is shown instead. Theme changes retain the artwork reference; use **Use generated cover** to see the chosen theme on the cover. Picker cancellation or failure keeps the current reference.

## Implementation

- `lib/core/models/book_design.dart`: immutable presets, per-book choices and defensive JSON parsing.
- `lib/core/models/book.dart`: optional `BookCoverRef.design`; legacy covers without it retain their original appearance.
- `lib/core/theme/book_visuals.dart`: reusable generated closed cover, quill and textured page surface.
- `lib/features/bookshelf/cover_editor.dart`, `book_card.dart` and `bookshelf_screen.dart`: editor, preview and shelf integration.
- `lib/features/reader/reader_widgets.dart` and `reader_page_surface.dart`: themed page surfaces and gutter details in folded and unfolded views, without changing text controllers, navigation or animations. Decorations ignore pointer input.
- `lib/data/storage/book_store.dart` and `storage_platform.dart`: optional design inside the existing `cover` JSON object, portable image references and artwork picker.
- `test/book_design_test.dart` and `test/bookshelf_test.dart`: preset and JSON behavior, storage/reopen, rendering, editor and shelf integration.

The design is stored in both the existing shelf snapshot and `booknotes.json` cover metadata; no schema version change, page-file change, migration or new package is required. Exports include the metadata and referenced cover as before. An older version of the app that rewrites metadata without knowing `design` can discard these new choices. A linked book needs write permission to save customization. Android SAF artwork picking and device accessibility should be checked on a device; automated storage tests use the filesystem backend. Image documents selected through Android may not preview until saved and copied to the book's cover cache. Custom text colors from reader typography remain user-controlled and can affect contrast. The color picker offers a fixed palette rather than an arbitrary color input.

## Session 1 Part 2

Modified `book_visuals.dart`, `cover_editor.dart`, `reader_widgets.dart`, `test/book_design_test.dart`, and this document; added `reader_page_surface.dart`. Widget tests exercise all five designs in closed, single-page and spread layouts, as well as metadata, persistence, artwork fallback and a narrow editor with enlarged text. These are not golden-image tests; visual quality and Android artwork picking still need checking on actual devices.
