/* Thin C facade over MuPDF.
 *
 * MuPDF reports errors through fz_try/fz_catch (setjmp/longjmp), which Swift
 * cannot call across. Every entry point here catches internally and reports
 * failure through its return value instead.
 *
 * A document owns its own fz_context and a mutex; all calls on one document
 * are serialized, so a document may be shared between threads.
 */
#ifndef CMUPDF_H
#define CMUPDF_H

#include <stddef.h>
#include <stdint.h>

typedef struct sr_doc sr_doc;

typedef struct {
    int width;
    int height;
    int stride;     /* bytes per row */
    uint8_t *data;  /* RGB, 3 bytes per pixel, top-down */
} sr_image;

/* Returns NULL on failure and writes a message into err (may be NULL). */
sr_doc *sr_doc_open(const char *path, char *err, size_t errlen);
void sr_doc_close(sr_doc *doc);

int sr_doc_page_count(sr_doc *doc);

/* Page size in points (1/72 inch). Returns 0 on success, -1 on error. */
int sr_doc_page_size(sr_doc *doc, int page, float *width, float *height);

/* Renders a page at scale (1.0 == 72 dpi) on a white background.
   Returns NULL on error; free with sr_image_free. */
sr_image *sr_doc_render(sr_doc *doc, int page, float scale);
void sr_image_free(sr_image *img);

#endif /* CMUPDF_H */
