## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  crop = TRUE
)
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)

## ----dancing-banana-path------------------------------------------------------
path_dancing_banana <- system.file("img", "Rlogo-banana.tif",
  package = "ijtiff"
)
print(path_dancing_banana)

## ----read-dancing-banana------------------------------------------------------
library(ijtiff)
img_dancing_banana <- read_tif(path_dancing_banana)

## ----peek---------------------------------------------------------------------
print(img_dancing_banana)

## ----red-blue-green-banana, echo=FALSE, message=FALSE, out.width='100%', dpi=300----
d <- dim(img_dancing_banana)
reds <- purrr::map(seq_len(d[4]), ~ img_dancing_banana[, , 1, .]) |>
  purrr::reduce(cbind)
greens <- purrr::map(seq_len(d[4]), ~ img_dancing_banana[, , 2, .]) |>
  purrr::reduce(cbind)
blues <- purrr::map(seq_len(d[4]), ~ img_dancing_banana[, , 3, .]) |>
  purrr::reduce(cbind)
to_display <- array(0, dim = c(3 * nrow(reds), ncol(reds), 3, 1))
to_display[seq_len(nrow(reds)), , 1, ] <- reds
to_display[seq_len(nrow(reds)) + nrow(reds), , 2, ] <- greens
to_display[seq_len(nrow(reds)) + 2 * nrow(reds), , 3, ] <- blues
display(to_display)

## ----threefiveseven-----------------------------------------------------------
img_dancing_banana357 <- read_tif(path_dancing_banana, frames = c(3, 5, 7))

## ----red-bblue-green-banana357, echo=FALSE, message=FALSE, out.width='100%', dpi=300----
d <- dim(img_dancing_banana357)
reds <- purrr::map(seq_len(d[4]), ~ img_dancing_banana357[, , 1, .]) |>
  purrr::reduce(cbind)
greens <- purrr::map(seq_len(d[4]), ~ img_dancing_banana357[, , 2, .]) |>
  purrr::reduce(cbind)
blues <- purrr::map(seq_len(d[4]), ~ img_dancing_banana357[, , 3, .]) |>
  purrr::reduce(cbind)
to_display <- array(0, dim = c(3 * nrow(reds), ncol(reds), 3, 1))
to_display[seq_len(nrow(reds)), , 1, ] <- reds
to_display[seq_len(nrow(reds)) + nrow(reds), , 2, ] <- greens
to_display[seq_len(nrow(reds)) + 2 * nrow(reds), , 3, ] <- blues
display(to_display)

## ----one-frame, dpi=300, out.width='90%'--------------------------------------
path_rlogo <- system.file("img", "Rlogo.tif", package = "ijtiff")
img_rlogo <- read_tif(path_rlogo)
dim(img_rlogo) # 4 channels, 1 frame
class(img_rlogo)
display(img_rlogo)

## ----one-channel, dpi=300, out.width='90%'------------------------------------
path_rlogo_grey <- system.file("img", "Rlogo-grey.tif", package = "ijtiff")
img_rlogo_grey <- read_tif(path_rlogo_grey)
dim(img_rlogo_grey) # 1 channel, 1 frame
display(img_rlogo_grey)

## ----write-tif----------------------------------------------------------------
path <- tempfile(pattern = "dancing-banana", fileext = ".tif")
print(path)
write_tif(img_dancing_banana, path)

## ----read-txt-img-------------------------------------------------------------
path_txt_img <- system.file("img", "Rlogo-grey.txt", package = "ijtiff")
txt_img <- read_txt_img(path_txt_img)

## ----write-txt-img------------------------------------------------------------
write_txt_img(txt_img, path = tempfile(pattern = "txtimg", fileext = ".txt"))

