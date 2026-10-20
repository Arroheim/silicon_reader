/* Thin C facade over MuPDF.
 *
 * MuPDF reports errors through fz_try/fz_catch (setjmp/longjmp), which Swift
 * cannot call across. Every entry point here catches internally and reports
 * failure through its return value instead.
 *
 * A document owns its own fz_context and a mutex; all calls on one document
 * are serialized, so a document may be shared between threads.
 *
 * Geometry is in page points with the origin at the top-left corner, y down.
 */
#ifndef CMUPDF_H
#define CMUPDF_H

#include <stddef.h>
#include <stdint.h>

typedef struct sr_doc sr_doc;

typedef struct {
    float x0, y0, x1, y1;
} sr_rect;

/* ----- document ----- */

/* Returns NULL on failure and writes a message into err (may be NULL).
   A password-protected document opens successfully; check
   sr_doc_needs_password before using it. */
sr_doc *sr_doc_open(const char *path, char *err, size_t errlen);
void sr_doc_close(sr_doc *doc);

/* 1 if the document is locked until sr_doc_authenticate succeeds. */
int sr_doc_needs_password(sr_doc *doc);
/* Returns non-zero when the password unlocks the document. */
int sr_doc_authenticate(sr_doc *doc, const char *password);

int sr_doc_page_count(sr_doc *doc);

/* Copies a metadata value (FZ_META_* key, e.g. "info:Title") into buf.
   Returns the value length, or -1 if absent. */
int sr_doc_metadata(sr_doc *doc, const char *key, char *buf, size_t size);

/* ----- pages ----- */

/* Page size in points (1/72 inch). Returns 0 on success, -1 on error. */
int sr_doc_page_size(sr_doc *doc, int page, float *width, float *height);

/* Copies the page label (e.g. "iv") into buf. Returns 0 if the page has a
   label, -1 otherwise. */
int sr_doc_page_label(sr_doc *doc, int page, char *buf, int size);

typedef struct {
    int width;
    int height;
    int stride;     /* bytes per row */
    uint8_t *data;  /* RGB, 3 bytes per pixel, top-down */
} sr_image;

/* Renders a page at scale (1.0 == 72 dpi) on a white background. region (in
   page points) limits the output to that part of the page; NULL renders the
   whole page. Returns NULL on error; free with sr_image_free. */
sr_image *sr_doc_render(sr_doc *doc, int page, float scale, const sr_rect *region);
void sr_image_free(sr_image *img);

/* Bounding box of everything drawn on the page, in page points. Returns 0 on
   success, -1 on error or for an empty page. */
int sr_doc_content_box(sr_doc *doc, int page, sr_rect *box);

/* ----- destinations ----- */

/* Where a link or outline entry points: an in-document page (page >= 0,
   x/y may be NAN when unspecified) or an external uri (page == -1). */
typedef struct {
    int page;
    float x, y;
    char *uri;  /* NULL for internal destinations */
} sr_dest;

/* ----- outline ----- */

typedef struct sr_outline sr_outline;
struct sr_outline {
    char *title;
    sr_dest dest;
    int is_open;
    sr_outline *children;
    int count;
};

/* Returns a synthetic root whose children are the top-level entries, or NULL
   if the document has no outline. Free with sr_outline_free. */
sr_outline *sr_doc_outline(sr_doc *doc);
void sr_outline_free(sr_outline *root);

/* ----- links ----- */

typedef struct {
    sr_rect rect;
    sr_dest dest;
} sr_link;

typedef struct {
    sr_link *items;
    int count;
} sr_links;

/* Returns NULL on error; an empty list when the page has no links. */
sr_links *sr_doc_page_links(sr_doc *doc, int page);
void sr_links_free(sr_links *links);

/* ----- text ----- */

typedef struct {
    uint32_t codepoint;
    sr_rect rect;
    int line;  /* line index within the page; changes mark a line break */
} sr_char;

typedef struct {
    sr_char *chars;
    int count;
} sr_text;

/* Returns NULL on error; an empty text when the page has none. */
sr_text *sr_doc_page_text(sr_doc *doc, int page);
void sr_text_free(sr_text *text);

#endif /* CMUPDF_H */
