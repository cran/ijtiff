#include "common.h"
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>

#include <Rinternals.h>
#include <R_ext/Rdynload.h>

const ttag_t supported_tags[] = {
    TIFFTAG_IMAGEWIDTH,
    TIFFTAG_IMAGELENGTH,
    TIFFTAG_IMAGEDEPTH,
    TIFFTAG_BITSPERSAMPLE,
    TIFFTAG_SAMPLESPERPIXEL,
    TIFFTAG_SAMPLEFORMAT,
    TIFFTAG_PLANARCONFIG,
    TIFFTAG_ROWSPERSTRIP,
    TIFFTAG_TILEWIDTH,
    TIFFTAG_TILELENGTH,
    TIFFTAG_COMPRESSION,
    TIFFTAG_THRESHHOLDING,
    TIFFTAG_XRESOLUTION,
    TIFFTAG_YRESOLUTION,
    TIFFTAG_XPOSITION,
    TIFFTAG_YPOSITION,
    TIFFTAG_RESOLUTIONUNIT,
    TIFFTAG_ORIENTATION,
    TIFFTAG_COPYRIGHT,
    TIFFTAG_ARTIST,
    TIFFTAG_DOCUMENTNAME,
    TIFFTAG_DATETIME,
    TIFFTAG_IMAGEDESCRIPTION,
    TIFFTAG_SOFTWARE,
    TIFFTAG_PHOTOMETRIC,
    TIFFTAG_COLORMAP
};

const size_t n_supported_tags = sizeof(supported_tags) / sizeof(ttag_t);

static int need_init = 1;
static int err_reenter = 0;

// Global variable to track the last opened TIFF handle
TIFF *last_tiff = NULL;

static char txtbuf[2048];  // text buffer

// avoid protection issues with setAttrib
void setAttr(SEXP x, const char *name, SEXP val) {
  PROTECT(val);
  setAttrib(x, Rf_install(name), val);
  UNPROTECT(1);  // UNPROTECT val
}

// avoid protection issues with getAttrib
SEXP getAttr(SEXP x, const char *name) {
  SEXP attr_name = PROTECT(mkString(name));
  SEXP out = PROTECT(getAttrib(x, attr_name));
  UNPROTECT(2);  // UNPROTECT attr_name and out
  return out;
}

static void TIFFWarningHandler_(const char* module, const char* fmt,
                                va_list ap) {
  /* we can't pass it directly since R has no vprintf entry point */
  vsnprintf(txtbuf, sizeof(txtbuf), fmt, ap);
  if (strstr(txtbuf,
             "Unknown field with tag") == NULL &&
        strstr(txtbuf,
               "Defining non-color channels as ExtraSamples.") == NULL) {
    Rf_warning("%s: %s", module, txtbuf);
  }
}

static void TIFFErrorHandler_(const char* module, const char* fmt, va_list ap) {
  if (err_reenter) return;
  /* prevent re-entrance which can happen as TIFF
     is happy to call another error from Close */
  err_reenter = 1;
  /* we can't pass it directly since R has no vprintf entry point */
  vsnprintf(txtbuf, sizeof(txtbuf), fmt, ap);
  /* we have to close the TIFF that caused it as it will not
     come back -- recursive calls won't work under errors
     but that is hopefully unlikely/impossible */
  Rf_warning("The tiff file you are attempting to read from is causing the "
               "following problem: \"%s: %s\"", module, txtbuf);
  if (last_tiff) TIFFClose(last_tiff); /* this will also reset last_tiff */
  err_reenter = 0;
  Rf_error("%s: %s", module, txtbuf);
}

static void init_tiff(void) {
  TIFFSetWarningHandler(TIFFWarningHandler_);
  TIFFSetErrorHandler(TIFFErrorHandler_);
  need_init = 0;
}

// Cleanup function to make sure all TIFF resources are released
void cleanup_tiff(void)
{
  if (last_tiff) {
    TIFFClose(last_tiff);
    last_tiff = NULL;
  }
}

static tsize_t TIFFReadProc_(thandle_t usr, tdata_t buf, tsize_t length) {
  tiff_job_t *rj = (tiff_job_t*) usr;  // rj is read_job
  tsize_t to_read = length;
  if (rj->f) return fread(buf, 1, to_read, rj->f);
  #if TIFF_DEBUG
    Rprintf("read [@%d %d/%d] -> %d\n", rj->ptr, rj->len, rj->alloc, length);
  #endif
  if (to_read > (rj->len - rj->ptr)) to_read = (rj->len - rj->ptr);
  if (to_read > 0) {
  	memcpy(buf, rj->data + rj->ptr, to_read);
	  rj->ptr += to_read;
  }
  return to_read;
}

static int guarantee_write_buffer(tiff_job_t *rj, long where) {
  if (where > rj->alloc) { // if need to resize buffer
  	void *new_data;
	  unsigned long new_alloc = rj->alloc;
  	while (new_alloc <= where) new_alloc <<= 1;
	  new_data = realloc(rj->data, new_alloc);
	  if (!new_data) {// if FAILED to resize
	    return 0;
	  }
	  rj->data = new_data;
	  rj->alloc = new_alloc;
  }
  return 1;
}

static tsize_t TIFFWriteProc_(thandle_t usr, tdata_t buf, tsize_t length) {
  tiff_job_t *rj = (tiff_job_t*) usr;
  if (rj->f) return (tsize_t) fwrite(buf, 1, length, rj->f);
  #if TIFF_DEBUG
    Rprintf("write [@%d %d/%d] <- %d\n", rj->ptr, rj->len, rj->alloc, length);
  #endif
  if (!guarantee_write_buffer(rj, rj->ptr + length)) return 0;
  memcpy(rj->data + rj->ptr, buf, length);
  rj->ptr += length;
  if (rj->ptr > rj->len) rj->len = rj->ptr;
  return length;
}

static toff_t  TIFFSeekProc_(thandle_t usr, toff_t offset, int whence) {
  tiff_job_t *rj = (tiff_job_t*) usr;
  if (rj->f) {
  	int e = fseeko(rj->f, offset, whence);
	  if (e != 0) {
	    Rf_warning("fseek failed on a file in TIFFSeekProc");
	    return -1;
	  }
	return ftello(rj->f);
  }
  #if TIFF_DEBUG
    Rprintf("seek [@%d %d/%d]  %d (%d)\n", rj->ptr, rj->len, rj->alloc, offset, whence);
  #endif
  if (whence == SEEK_CUR)	{
    offset += rj->ptr;
  } else if (whence == SEEK_END) {
  	offset += rj->len;
  } else if (whence != SEEK_SET) {
  	Rf_warning("invalid `whence' argument to TIFFSeekProc callback called by libtiff");
	  return -1;
  }
  if (rj->alloc && rj->len < offset) {
	  if (offset >= rj->alloc) { // if need more space
	    if (!guarantee_write_buffer(rj, offset)) {
		    return -1;
	    }
	  } else {  // enough space but need to zero out
	    memset(rj->data + rj->len, 0, offset - rj->len);
	  }
	  rj->len = offset;
  }

  if (offset > rj->len) {
	  Rf_warning("libtiff attempted to seek beyond the data end");
	  return -1;
  }
  return (toff_t) (rj->ptr = offset);
}

static int TIFFCloseProc_(thandle_t usr) {
  tiff_job_t *rj = (tiff_job_t*) usr;
  if (rj->f) {
    fclose(rj->f);
    rj->f = NULL;
  } else if (rj->alloc) {
    free(rj->data);
    rj->data = NULL;
    rj->alloc = 0;
  }
  last_tiff = 0;
  return 0;
}

static toff_t TIFFSizeProc_(thandle_t usr) {
  tiff_job_t *rj = (tiff_job_t*) usr;
  if (rj->f) {
	  off_t cur = ftello(rj->f), end;
  	fseek(rj->f, 0, SEEK_END);
  	end = ftello(rj->f);
	  fseeko(rj->f, cur, SEEK_SET);
	  return end;
  }
  return (toff_t) rj->len;
}

static int TIFFMapFileProc_(thandle_t usr, tdata_t* map, toff_t* off) {
  Rf_warning("libtiff attempted to use TIFFMapFileProc on non-file which is unsupported");
  return -1;
}

static void TIFFUnmapFileProc_(thandle_t usr, tdata_t map, toff_t off) {
  Rf_warning("libtiff attempted to use TIFFUnmapFileProc on non-file which is unsupported");
}

/* actual interface */
TIFF *TIFF_Open(const char *mode, tiff_job_t *rj) {
  if (need_init) init_tiff();
  
  // Always close the previous TIFF handle to prevent memory leaks
  if (last_tiff) {
    TIFFClose(last_tiff);
    last_tiff = NULL;
  }
  
  // Verify that the file appears to be a valid TIFF before attempting to open it
  // Only do this check for read operations (mode contains 'r')
  if (rj->f && strchr(mode, 'r') != NULL) {
    // Check for TIFF magic number (II or MM followed by version)
    char magic[4];
    long pos = ftell(rj->f);
    size_t read = fread(magic, 1, 4, rj->f);
    fseek(rj->f, pos, SEEK_SET); // Reset file position
    
    // Check TIFF signature: II (Intel) or MM (Motorola) followed by version (usually 42)
    if (read != 4 || 
        !((magic[0] == 'I' && magic[1] == 'I' && magic[2] == 42 && magic[3] == 0) || 
          (magic[0] == 'M' && magic[1] == 'M' && magic[2] == 0 && magic[3] == 42))) {
      // Not a valid TIFF file, don't even try TIFFClientOpen
      return NULL;
    }
  }
  
  // Store the result directly in last_tiff so we can clean it up on error
  last_tiff = TIFFClientOpen("pkg:ijtiff", mode, (thandle_t) rj, TIFFReadProc_,
                         TIFFWriteProc_, TIFFSeekProc_, TIFFCloseProc_,
                         TIFFSizeProc_, TIFFMapFileProc_, TIFFUnmapFileProc_);
  
  // If TIFFClientOpen failed, make sure we don't return a NULL pointer
  // The memory leak in TIFFClientOpen would have already happened, but
  // this ensures we properly handle future cleanup
  return last_tiff;
}

// Helper function to open a TIFF file
TIFF* open_tiff_file(const char* filename, tiff_job_t* rj, FILE** f) {
    *f = fopen(filename, "rb");
    if (!*f) {
        Rf_error("Unable to open %s", filename);
    }
    rj->f = *f;
    TIFF* tiff = TIFF_Open("rmc", rj); // no mmap, no chopping
    if (!tiff) {
        fclose(*f);
        *f = NULL;
        rj->f = NULL;
        Rf_error("Unable to open as TIFF file: %s does not appear to be a valid TIFF file", filename);
    }
    return tiff;
}

void check_type_sizes(void) {
  unsigned int sz = sizeof(uint8_t) * CHAR_BIT;
  if (sz != 8) {
    Rf_error("Usually, the size of the \'uint8_t\' type is 8 bits, "
               "however on your system it is %i. The \'ijtiff\' library relies "
               "on \'uint8_t\' being 8-bit, so it will not work "
               "on your system.", sz);
  }
  sz = sizeof(uint16_t) * CHAR_BIT;
  if (sz != 16) {
    Rf_error("Usually, the size of the \'uint16_t\' type is 16 bits, "
               "however on your system it is %i. The \'ijtiff\' library relies "
               "on \'uint16_t\' being 16-bit, so it will not "
               "work on your system.", sz);
  }
  sz = sizeof(uint32_t) * CHAR_BIT;
  if (sz != 32) {
    Rf_error("Usually, the size of the \'uint32_t\' type is 32 bits, "
               "however on your system it is %i. The \'ijtiff\' library relies "
               "on \'uint32_t\' being 32-bit, so it will not work "
               "on your system.", sz);
  }
  sz = sizeof(uint64_t) * CHAR_BIT;
  if (sz != 64) {
    Rf_error("Usually, the size of the \'uint64_t\' type is "
               "64 bits, however on your system it is %i. The \'ijtiff\' "
               "library relies on \'uint64_t\' being 32-bit, so it will not"
               " work on your system.", sz);
  }
  sz = sizeof(float) * CHAR_BIT;
  if (sz != 32) {
    Rf_error("Usually, the size of the \'float\' type is 32 bits, "
               "however on your system it is %i. The \'ijtiff\' library relies "
               "on \'float\' being 32-bit, so it will not work "
               "on your system.", sz);
  }
}
