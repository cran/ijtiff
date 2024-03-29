#' Basic image display.
#'
#' Display an image that has been read in by [read_tif()] as it would look in
#' 'ImageJ'. This function is really just [EBImage::display()] on the inside. If
#' you do not have `EBImage` installed, a more basic display is offered.
#'
#' @param img An [ijtiff_img] object.
#' @param method The way of displaying images. Defaults to "browser" when R is
#'   used interactively, and to "raster" otherwise. The default behavior can be
#'   overridden by setting options("EBImage.display"). This has no effect when
#'   `basic = TRUE`.
#' @param basic Force the basic (non-`EBImage`) display.
#' @param normalize Normalize the image before displaying (for better contrast)?
#'   This only has an effect if the EBImage functionality is used. The basic
#'   display always normalizes.
#'
#' @examples
#' if (requireNamespace("EBImage")) {
#'   img <- read_tif(system.file("img", "Rlogo.tif", package = "ijtiff"))
#'   display(img)
#'   display(img[, , 1, 1]) # first (red) channel, first frame
#'   display(img[, , 2, ]) # second (green) channel, first frame
#'   display(img[, , 3, ]) # third (blue) channel, first frame
#'   display(img, basic = TRUE) # displays first (red) channel, first frame
#' }
#' @export
display <- function(img, method = NULL, basic = FALSE, normalize = TRUE) {
  if (basic) {
    ld <- length(dim(img))
    if (ld == 4) img <- img[, , 1, 1]
    if (ld == 3) img <- img[, , 1]
    checkmate::assert_matrix(img)
    img <- t(img[rev(seq_len(nrow(img))), ])
    graphics::image(img,
      col = grDevices::grey.colors(999, 0, 1),
      xaxt = "n", yaxt = "n"
    )
  } else {
    if (rlang::is_installed("EBImage")) {
      if (!methods::is(img, "Image")) img <- as_EBImage(img)
      if (normalize) img <- EBImage::normalize(img)
      if (is.null(method)) {
        EBImage::display(img, method = "raster")
      } else {
        checkmate::assert_string(method)
        method <- strex::match_arg(method, c("browser", "raster"),
          ignore_case = TRUE
        )
        EBImage::display(img, method = method)
      }
    } else {
      message(
        "Using basic display functionality.", "\n",
        "  * For better display functionality, ",
        "install the EBImage package.", "\n",
        ebimg_install_msg()
      )
      display(img, basic = TRUE)
    }
  }
}
