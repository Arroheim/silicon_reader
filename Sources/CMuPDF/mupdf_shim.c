#include "CMuPDF.h"

#include <mupdf/fitz.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct sr_doc {
    fz_context *ctx;
    fz_document *doc;
    pthread_mutex_t lock;
};

static void copy_error(fz_context *ctx, char *err, size_t errlen) {
    if (err == NULL || errlen == 0) {
        return;
    }
    const char *msg = ctx ? fz_caught_message(ctx) : "cannot create MuPDF context";
    strncpy(err, msg, errlen - 1);
    err[errlen - 1] = '\0';
}

sr_doc *sr_doc_open(const char *path, char *err, size_t errlen) {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        copy_error(NULL, err, errlen);
        return NULL;
    }

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

int sr_doc_page_count(sr_doc *d) {
    int n = -1;
    pthread_mutex_lock(&d->lock);
    fz_try(d->ctx) {
        n = fz_count_pages(d->ctx, d->doc);
    }
    fz_catch(d->ctx) {
        n = -1;
    }
    pthread_mutex_unlock(&d->lock);
    return n;
}

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
