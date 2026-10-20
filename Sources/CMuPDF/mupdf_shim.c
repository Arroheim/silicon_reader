#include "CMuPDF.h"

#include <dispatch/dispatch.h>
#include <math.h>
#include <mupdf/fitz.h>
#include <os/log.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct sr_doc {
    fz_context *ctx;
    fz_document *doc;
    pthread_mutex_t lock;
};

static os_log_t mupdf_log(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("io.github.arroheim.siliconreader", "mupdf");
    });
    return log;
}

/* MuPDF prints to stderr by default; route its diagnostics to the unified log. */
static void log_warning(void *user, const char *message) {
    (void)user;
    os_log(mupdf_log(), "%{public}s", message);
}

static void log_error(void *user, const char *message) {
    (void)user;
    os_log_error(mupdf_log(), "%{public}s", message);
}

static void copy_error(fz_context *ctx, char *err, size_t errlen) {
    if (err == NULL || errlen == 0) {
        return;
    }
    const char *msg = ctx ? fz_caught_message(ctx) : "cannot create MuPDF context";
    strncpy(err, msg, errlen - 1);
    err[errlen - 1] = '\0';
}

static char *dup_string(const char *s) {
    return s ? strdup(s) : NULL;
}

/* ----- document ----- */

sr_doc *sr_doc_open(const char *path, char *err, size_t errlen) {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        copy_error(NULL, err, errlen);
        return NULL;
    }
    fz_set_warning_callback(ctx, log_warning, NULL);
    fz_set_error_callback(ctx, log_error, NULL);

    fz_document *doc = NULL;
    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path);
    }
    fz_catch(ctx) {
        copy_error(ctx, err, errlen);
        fz_drop_context(ctx);
        return NULL;
    }

    sr_doc *d = calloc(1, sizeof(*d));
    d->ctx = ctx;
    d->doc = doc;
    pthread_mutex_init(&d->lock, NULL);
    return d;
}

void sr_doc_close(sr_doc *d) {
    if (d == NULL) {
        return;
    }
    fz_drop_document(d->ctx, d->doc);
    fz_drop_context(d->ctx);
    pthread_mutex_destroy(&d->lock);
    free(d);
}

int sr_doc_needs_password(sr_doc *d) {
    int needs = 0;
    pthread_mutex_lock(&d->lock);
    fz_try(d->ctx) {
        needs = fz_needs_password(d->ctx, d->doc);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        needs = 0;
    }
    pthread_mutex_unlock(&d->lock);
    return needs;
}

int sr_doc_authenticate(sr_doc *d, const char *password) {
    int ok = 0;
    pthread_mutex_lock(&d->lock);
    fz_try(d->ctx) {
        ok = fz_authenticate_password(d->ctx, d->doc, password);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        ok = 0;
    }
    pthread_mutex_unlock(&d->lock);
    return ok;
}

int sr_doc_page_count(sr_doc *d) {
    int n = -1;
    pthread_mutex_lock(&d->lock);
    fz_try(d->ctx) {
        n = fz_count_pages(d->ctx, d->doc);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        n = -1;
    }
    pthread_mutex_unlock(&d->lock);
    return n;
}

int sr_doc_metadata(sr_doc *d, const char *key, char *buf, size_t size) {
    int len = -1;
    pthread_mutex_lock(&d->lock);
    fz_try(d->ctx) {
        len = fz_lookup_metadata(d->ctx, d->doc, key, buf, size);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        len = -1;
    }
    pthread_mutex_unlock(&d->lock);
    return len;
}

/* ----- pages ----- */

int sr_doc_page_size(sr_doc *d, int page, float *width, float *height) {
    int rc = 0;
    fz_page *p = NULL;
    pthread_mutex_lock(&d->lock);
    fz_var(p);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        fz_rect r = fz_bound_page(d->ctx, p);
        *width = r.x1 - r.x0;
        *height = r.y1 - r.y0;
    }
    fz_always(d->ctx) {
        fz_drop_page(d->ctx, p);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        rc = -1;
    }
    pthread_mutex_unlock(&d->lock);
    return rc;
}

int sr_doc_page_label(sr_doc *d, int page, char *buf, int size) {
    int rc = -1;
    fz_page *p = NULL;
    pthread_mutex_lock(&d->lock);
    fz_var(p);
    fz_var(rc);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        buf[0] = '\0';
        fz_page_label(d->ctx, p, buf, size);
        rc = buf[0] != '\0' ? 0 : -1;
    }
    fz_always(d->ctx) {
        fz_drop_page(d->ctx, p);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        rc = -1;
    }
    pthread_mutex_unlock(&d->lock);
    return rc;
}

sr_image *sr_doc_render(sr_doc *d, int page, float scale) {
    sr_image *img = NULL;
    fz_page *p = NULL;
    fz_pixmap *pix = NULL;
    fz_device *dev = NULL;

    pthread_mutex_lock(&d->lock);
    fz_var(p);
    fz_var(pix);
    fz_var(dev);
    fz_var(img);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        fz_matrix ctm = fz_scale(scale, scale);
        fz_irect bbox = fz_round_rect(fz_transform_rect(fz_bound_page(d->ctx, p), ctm));

        pix = fz_new_pixmap_with_bbox(d->ctx, fz_device_rgb(d->ctx), bbox, NULL, 0);
        fz_clear_pixmap_with_value(d->ctx, pix, 0xff);
        dev = fz_new_draw_device(d->ctx, fz_identity, pix);
        fz_run_page(d->ctx, p, dev, ctm, NULL);
        fz_close_device(d->ctx, dev);

        size_t size = (size_t)pix->stride * (size_t)pix->h;
        img = malloc(sizeof(*img));
        img->width = pix->w;
        img->height = pix->h;
        img->stride = (int)pix->stride;
        img->data = malloc(size);
        memcpy(img->data, pix->samples, size);
    }
    fz_always(d->ctx) {
        fz_drop_device(d->ctx, dev);
        fz_drop_pixmap(d->ctx, pix);
        fz_drop_page(d->ctx, p);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        sr_image_free(img);
        img = NULL;
    }
    pthread_mutex_unlock(&d->lock);
    return img;
}

void sr_image_free(sr_image *img) {
    if (img == NULL) {
        return;
    }
    free(img->data);
    free(img);
}

/* ----- destinations ----- */

/* Called with the lock held, inside fz_try. */
static sr_dest resolve_uri(sr_doc *d, const char *uri) {
    sr_dest dest = {.page = -1, .x = NAN, .y = NAN, .uri = NULL};
    if (uri == NULL || uri[0] == '\0') {
        return dest;
    }
    if (fz_is_external_link(d->ctx, uri)) {
        dest.uri = strdup(uri);
        return dest;
    }
    float x = NAN, y = NAN;
    fz_location loc = fz_resolve_link(d->ctx, d->doc, uri, &x, &y);
    if (loc.page >= 0) {
        dest.page = fz_page_number_from_location(d->ctx, d->doc, loc);
        dest.x = x;
        dest.y = y;
    }
    return dest;
}

/* ----- outline ----- */

static void outline_clear(sr_outline *item) {
    for (int i = 0; i < item->count; i++) {
        outline_clear(&item->children[i]);
    }
    free(item->children);
    free(item->title);
    free(item->dest.uri);
}

/* Converts the sibling chain starting at node into parent->children. */
static void outline_convert(sr_doc *d, fz_outline *node, sr_outline *parent) {
    int count = 0;
    for (fz_outline *n = node; n; n = n->next) {
        count++;
    }
    if (count == 0) {
        return;
    }
    parent->children = calloc((size_t)count, sizeof(sr_outline));
    for (fz_outline *n = node; n; n = n->next) {
        sr_outline *item = &parent->children[parent->count++];
        item->title = dup_string(n->title ? n->title : "");
        item->is_open = n->is_open;
        if (n->page.page >= 0) {
            item->dest = (sr_dest){
                .page = fz_page_number_from_location(d->ctx, d->doc, n->page), .x = n->x, .y = n->y, .uri = NULL};
        } else {
            item->dest = resolve_uri(d, n->uri);
        }
        outline_convert(d, n->down, item);
    }
}

sr_outline *sr_doc_outline(sr_doc *d) {
    sr_outline *root = NULL;
    fz_outline *outline = NULL;
    pthread_mutex_lock(&d->lock);
    fz_var(outline);
    fz_var(root);
    fz_try(d->ctx) {
        outline = fz_load_outline(d->ctx, d->doc);
        if (outline) {
            root = calloc(1, sizeof(*root));
            outline_convert(d, outline, root);
        }
    }
    fz_always(d->ctx) {
        fz_drop_outline(d->ctx, outline);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        sr_outline_free(root);
        root = NULL;
    }
    pthread_mutex_unlock(&d->lock);
    return root;
}

void sr_outline_free(sr_outline *root) {
    if (root == NULL) {
        return;
    }
    outline_clear(root);
    free(root);
}

/* ----- links ----- */

static sr_rect to_rect(fz_rect r) {
    return (sr_rect){r.x0, r.y0, r.x1, r.y1};
}

sr_links *sr_doc_page_links(sr_doc *d, int page) {
    sr_links *result = NULL;
    fz_page *p = NULL;
    fz_link *links = NULL;
    pthread_mutex_lock(&d->lock);
    fz_var(p);
    fz_var(links);
    fz_var(result);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        links = fz_load_links(d->ctx, p);
        int count = 0;
        for (fz_link *l = links; l; l = l->next) {
            count++;
        }
        result = calloc(1, sizeof(*result));
        result->items = calloc((size_t)(count > 0 ? count : 1), sizeof(sr_link));
        for (fz_link *l = links; l; l = l->next) {
            sr_dest dest = resolve_uri(d, l->uri);
            if (dest.page < 0 && dest.uri == NULL) {
                continue;  // unresolvable internal link
            }
            result->items[result->count++] = (sr_link){.rect = to_rect(l->rect), .dest = dest};
        }
    }
    fz_always(d->ctx) {
        fz_drop_link(d->ctx, links);
        fz_drop_page(d->ctx, p);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        sr_links_free(result);
        result = NULL;
    }
    pthread_mutex_unlock(&d->lock);
    return result;
}

void sr_links_free(sr_links *links) {
    if (links == NULL) {
        return;
    }
    for (int i = 0; i < links->count; i++) {
        free(links->items[i].dest.uri);
    }
    free(links->items);
    free(links);
}

/* ----- text ----- */

typedef struct {
    sr_char *chars;
    int count;
    int capacity;
    int line;
} text_builder;

static void text_append(text_builder *b, uint32_t codepoint, fz_rect rect) {
    if (b->count == b->capacity) {
        b->capacity = b->capacity ? b->capacity * 2 : 256;
        b->chars = realloc(b->chars, (size_t)b->capacity * sizeof(sr_char));
    }
    b->chars[b->count++] = (sr_char){.codepoint = codepoint, .rect = to_rect(rect), .line = b->line};
}

static void text_collect(fz_stext_block *block, text_builder *b) {
    for (; block; block = block->next) {
        if (block->type == FZ_STEXT_BLOCK_STRUCT && block->u.s.down) {
            text_collect(block->u.s.down->first_block, b);
        } else if (block->type == FZ_STEXT_BLOCK_TEXT) {
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next) {
                for (fz_stext_char *ch = line->first_char; ch; ch = ch->next) {
                    text_append(b, (uint32_t)ch->c, fz_rect_from_quad(ch->quad));
                }
                b->line++;
            }
        }
    }
}

sr_text *sr_doc_page_text(sr_doc *d, int page) {
    sr_text *result = NULL;
    fz_page *p = NULL;
    fz_stext_page *stext = NULL;
    pthread_mutex_lock(&d->lock);
    fz_var(p);
    fz_var(stext);
    fz_var(result);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        fz_stext_options opts;
        fz_init_stext_options(d->ctx, &opts);
        stext = fz_new_stext_page_from_page(d->ctx, p, &opts);

        text_builder b = {0};
        text_collect(stext->first_block, &b);
        result = malloc(sizeof(*result));
        result->chars = b.chars;
        result->count = b.count;
    }
    fz_always(d->ctx) {
        fz_drop_stext_page(d->ctx, stext);
        fz_drop_page(d->ctx, p);
    }
    fz_catch(d->ctx) {
        fz_report_error(d->ctx);
        sr_text_free(result);
        result = NULL;
    }
    pthread_mutex_unlock(&d->lock);
    return result;
}

void sr_text_free(sr_text *text) {
    if (text == NULL) {
        return;
    }
    free(text->chars);
    free(text);
}
