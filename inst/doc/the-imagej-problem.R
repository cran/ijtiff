## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  crop = TRUE
)
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)
library(magrittr)
par(mar = rep(0, 4))

## ----2 channel path-----------------------------------------------------------
path_2ch_ij <- system.file("img", "Rlogo-banana-red_green.tif",
  package = "ijtiff"
)

## ----red and green banana, echo=FALSE, message=FALSE, dpi=300, warning=FALSE, out.width='100%'----
rgbanana_tif <- system.file("img", "Rlogo-banana.tif",
  package = "ijtiff"
) %>%
  ijtiff::read_tif()
rgbanana_tif[is.na(rgbanana_tif)] <- max(rgbanana_tif, na.rm = TRUE)
d <- dim(rgbanana_tif)
reds <- cbind(rgbanana_tif[, , 1, 1], rgbanana_tif[, , 1, 3]) %>%
  apply(2, \(r) rgb(r, 0, 0, maxColorValue = max(rgbanana_tif, na.rm = TRUE)))
greens <- cbind(rgbanana_tif[, , 2, 1], rgbanana_tif[, , 2, 3]) %>%
  apply(2, \(g) rgb(0, g, 0, maxColorValue = max(rgbanana_tif, na.rm = TRUE)))
to_display <- as.raster(rbind(reds, greens))
graphics::plot(to_display)

## ----original tiff import-----------------------------------------------------
img <- tiff::readTIFF(path_2ch_ij, all = TRUE)
str(img)
img[[1]][100:105, 50:55, 1] # print a section of the first image in the series

## ----ijtiff import------------------------------------------------------------
img <- ijtiff::read_tif(path_2ch_ij)
dim(img) # 2 channels, 2 frames
img[100:105, 50:55, 1, 1] # print a section of the first channel, first frame

