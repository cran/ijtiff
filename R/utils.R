#' Prep an [ijtiff_img]-style array for `write_tif_C()`.
#'
#' It has to be a list of 3-dimensional arrays. Heavy lifting done in C++ by
#' `enlist_img_cpp()`.
#'
#' @param img An [ijtiff_img]-style array.
#'
#' @return A list.
#'
#' @noRd
enlist_img <- function(img) {
  checkmate::assert_array(img, d = 4, mode = "double")
  .Call("enlist_img_C", img, PACKAGE = "ijtiff")
}

#' Split the planes of a 3D array into a list.
#'
#' Planes are along the 3rd dimension.
#'
#' @param arr3d A 3D array.
#'
#' @return A list of 2D arrays.
#'
#' @noRd
enlist_planes <- function(arr3d) {
  checkmate::assert_array(arr3d, d = 3, mode = "double")
  .Call("enlist_planes_C", arr3d, PACKAGE = "ijtiff")
}

#' Calculate [dim()] on every element in a list.
#'
#' @param lst A list.
#'
#' @return A list.
#'
#' @noRd
dims <- function(lst) {
  checkmate::assert_list(lst)
  .Call("dims_C", lst, PACKAGE = "ijtiff")
}

#' Extract the appropriate plane.
#'
#' Sometimes the TIFF reading is weird and you get more planes than you wanted,
#' but one of them is clearly the right one. This function will pluck that out
#' for you.
#'
#' @param arr An array. Mostly 3D. If 2D, input is returned.
#'
#' @return A 2D array.
#'
#' @noRd
extract_desired_plane <- function(arr) {
  checkmate::assert_array(arr, min.d = 2, max.d = 3)
  d <- dim(arr)
  if (length(d) == 3) {
    nonzero_planes <- !purrr::map_lgl(
      seq_len(d[3]),
      ~ isTRUE(unique(as.vector(arr[, , .])) == 0)
    )
    if (sum(nonzero_planes) == 1) {
      arr <- arr[, , nonzero_planes]
    } else if (dplyr::n_distinct(enlist_planes(arr)) == 1) {
      arr <- arr[, , 1]
    } else {
      n_nonzero_unique_planes <- arr %>%
        enlist_planes() %>%
        unique() %>%
        length()
      rlang::abort(
        c("Cannot extract the desired plane.",
          x = stringr::str_glue(
            "There are {n_nonzero_unique_planes} unique nonzero ",
            "planes, so it is impossible to decipher which is the ",
            "correct one to extract."
          )
        )
      )
    }
  }
  arr
}

#' Compute the desired plane.
#'
#' This function wraps [extract_desired_plane()]. Sometimes the TIFF reading is
#' weird and you get more planes than you wanted, but one of them is clearly the
#' right one. This function will pluck that out for you. If the images have a
#' color palette, that conversion takes place here too.
#'
#' @inheritParams extract_desired_plane
#'
#' @return A 2D array.
#'
#' @noRd
compute_desired_plane <- function(arr) {
  att_names <- names(attributes(arr))
  if (all(c("PhotometricInterpretation", "ColorMap") %in% att_names) &&
    isTRUE(attr(arr, "PhotometricInterpretation") == "Palette")) {
    return(match_pillar_to_row_3(arr, attr(arr, "ColorMap", exact = TRUE)))
  }
  extract_desired_plane(arr)
}

#' Find the lowest number that is bigger than all the elements in `x`.
#'
#' @param x A numeric vector.
#' @param possible_upper_bounds A numeric vector.
#' @param na_rm Ignore `NA`s?
#'
#' @return A number.
#'
#' @noRd
lowest_upper_bound <- function(x, possible_upper_bounds, na_rm = TRUE) {
  checkmate::assert_numeric(x, min.len = 1)
  checkmate::assert_numeric(possible_upper_bounds, min.len = 1)
  checkmate::assert_flag(na_rm)
  if (anyNA(x) && rlang::is_false(na_rm)) {
    return(NA_real_)
  }
  mx <- suppressWarnings(max(as.vector(x), na.rm = na_rm))
  if (is.na(mx) || is.infinite(mx)) {
    return(NA_real_)
  }
  possible_upper_bounds <- sort(possible_upper_bounds)
  for (pub in possible_upper_bounds) {
    if (pub >= mx) {
      return(pub)
    }
  }
  return(NA_real_)
}

#' Does the object read by `read_tif_C()` have a colormap or channels specified
#' in the weird ImageJ way?
#'
#' @param img_lst A list. The output of `read_tif_C()`.
#' @param prep The output of a call to `prep_read()`.
#' @param d The dimension of the images in `img_lst`.
#'
#' @return A flag.
#'
#' @noRd
colormap_or_ij_channels <- function(img_lst, prep, d) {
  weird_ij_channels <- (isTRUE(length(img_lst) == prep$n_imgs) && prep$ij_n_ch)
  colormap <- (!prep$ij_n_ch && prep$n_ch == 1) && (length(d) > 2)
  colormap || weird_ij_channels
}

#' Count the number of frames in a TIFF file.
#'
#' TIFF files can hold many frames. Often this is sensible, e.g. each frame
#' could be a time-point in a video or a slice of a z-stack.
#'
#' For those familiar with TIFF files, this function counts the number of
#' directories in a TIFF file. There is an adjustment made for some
#' ImageJ-written TIFF files.
#'
#' @inheritParams read_tif
#'
#' @return A number, the number of frames in the TIFF file. This has an
#'   attribute `n_dirs` which holds the true number of directories in the TIFF
#'   file, making no allowance for the way ImageJ may write TIFF files.
#'
#' @examples
#' count_frames(system.file("img", "Rlogo.tif", package = "ijtiff"))
#' @export
count_frames <- function(path) {
  path <- fs::path_expand(path)
  prep <- prep_read(path,
    frames = "all",
    tags1 = read_tags(path, frames = 1)[[1]]
  )
  out <- ifelse(is.na(prep$n_slices), prep$n_dirs, prep$n_slices)
  attr(out, "n_dirs") <- prep$n_dirs
  out
}

#' @rdname count_frames
#' @export
frames_count <- function(path) {
  count_frames(path = path)
}

#' Is a numeric vector equal to its floor.
#'
#' This is different to [checkmate::check_integerish()] as it permits things
#' outside the 32-bit integer range.
#'
#' @param x A numeric vector.
#'
#' @return A flag.
#'
#' @noRd
can_be_intish <- function(x) isTRUE(all(x == floor(x)))

#' Check if an object is an [EBImage::Image].
#'
#' @param x An object.
#'
#' @return A flag.
#'
#' @noRd
is_EBImage <- function(x) {
  suppressWarnings(
    isTRUE("Image" %in% class(x)) &&
      isTRUE(attr(class(x), "package") == "EBImage")
  )
}

#' A message to tell the user to install EBImage.
#'
#' @return A string.
#'
#' @noRd
ebimg_install_msg <- function() {
  paste0(
    "  * To install `EBImage`:", "\n",
    "    - Install `BiocManager` with `install.packages(\"BiocManager\")`.\n",
    "    - Then run `BiocManager::install(\"EBImage\")`."
  )
}

#' Rejig linescan images.
#'
#' `ijtiff` has the fourth dimension of an [ijtiff_img] as its time dimension.
#' However, some linescan images (images where a single line of pixels is
#' acquired over and over) have the time dimension as the y dimension, (to avoid
#' the need for an image stack). These functions allow one to convert this type
#' of image into a conventional [ijtiff_img] (with time in the fourth dimension)
#' and to convert back.
#'
#' @param linescan_img A 4-dimensional array in which the time axis is the first
#'   axis. Dimension 4 must be 1 i.e. `dim(linescan_img)[4] == 1`.
#' @param img A conventional [ijtiff_img], to be turned into a linescan image.
#'   Dimension 1 must be 1 i.e. `dim(img)[1] == 1`.
#'
#' @return The converted image, an object of class [ijtiff_img].
#'
#' @examples
#' linescan <- ijtiff_img(array(rep(1:4, each = 4), dim = c(4, 4, 1, 1)))
#' print(linescan)
#' stack <- linescan_to_stack(linescan)
#' print(stack)
#' linescan <- stack_to_linescan(stack)
#' print(linescan)
#' @name linescan-conversion
NULL

#' @rdname linescan-conversion
#' @export
linescan_to_stack <- function(linescan_img) {
  linescan_img <- ijtiff_img(linescan_img)
  if (dim(linescan_img)[4] != 1) {
    rlang::abort(
      c(
        paste(
          "The fourth dimension of `linescan_img` should be equal to 1",
          "(or else it's not a linescan image)."
        ),
        stringr::str_glue(
          "Yours has ",
          "`dim(linescan_img)[4] == {dim(linescan_img)[4]}`."
        )
      )
    )
  }
  linescan_img %>%
    aperm(c(4, 2, 3, 1)) %>%
    ijtiff_img()
}

#' @rdname linescan-conversion
#' @export
stack_to_linescan <- function(img) {
  img <- ijtiff_img(img)
  if (dim(img)[1] != 1) {
    rlang::abort(
      c(
        paste(
          "The first dimension of `img` should be equal to 1 (or",
          "else it's not a stack that can be converted to a linescan)."
        ),
        x = stringr::str_glue("Yours has dim(img)[1] == {dim(img)[1]}.")
      )
    )
  }
  img %>%
    aperm(c(4, 2, 3, 1)) %>%
    ijtiff_img()
}

#' TIFF tag reference.
#'
#' A dataset containing the information on all known baseline and extended TIFF
#' tags.
#'
#' A data frame with 96 rows and 10 variables: \describe{
#' \item{code_dec}{decimal numeric code of the TIFF tag}
#' \item{code_hex}{hexadecimal numeric code of the TIFF tag} \item{name}{the
#' name of the TIFF tag} \item{short_description}{a short description of the
#' TIFF tag} \item{tag_type}{the type of TIFF tag: either "baseline" or
#' "extended"} \item{url}{the URL of the TIFF tag at
#' \url{https://www.awaresystems.be}} \item{libtiff_name}{the TIFF tag name in
#' the libtiff C library} \item{c_type}{the C type of the TIFF tag data in
#' libtiff} \item{count}{the number of elements in the TIFF tag data}
#' \item{default}{the default value of the data held in the TIFF tag} }
#' @source \url{https://www.awaresystems.be}
#'
#' @examples
#' tif_tags_reference()
#' @export
tif_tags_reference <- function() {
  "TIFF_tags.csv" %>%
    system.file("extdata", ., package = "ijtiff") %>%
    readr::read_csv(., col_types = readr::cols())
}

#' Check that the `frames` argument has been passed correctly.
#'
#' @param frames An integerish vector. The requested frames.
#'
#' @return `TRUE` invisibly if everything is OK. The function errors otherwise.
#'
#' @noRd
prep_frames <- function(frames) {
  checkmate::assert(
    checkmate::check_string(frames),
    checkmate::check_integerish(frames, lower = 1)
  )
  if (is.character(frames)) {
    frames <- tolower(frames)
    if (!startsWith("all", frames)) {
      rlang::abort(
        c("If `frames` is a string, it must be 'all'.",
          x = stringr::str_glue("You have `frames = '{frames}'`.")
        )
      )
    }
    frames <- "all"
  }
  frames
}

#' Calculate the number of slices from an ImageJ `ImageDescription`.
#'
#' @param ij_description A string.
#'
#' @return A number.
#'
#' @noRd
calculate_n_slices <- function(ij_description) {
  n_slices <- strex::str_first_number_after_first(ij_description, "slices=")
  if (stringr::str_detect(ij_description, "frames=")) {
    n_frames <- strex::str_first_number_after_first(
      ij_description,
      "frames="
    )
    if (!is.na(n_slices) && rlang::is_false(n_frames == n_slices)) {
      if (isTRUE(n_slices == 1) || isTRUE(n_frames == 1)) {
        n_slices <- n_frames <- max(n_slices, n_frames)
      } else {
        rlang::abort(
          c(
            stringr::str_glue(
              "The ImageJ-written image you're trying to read says it ",
              "has {n_frames} frames AND {n_slices} slices."
            ),
            x = paste(
              "To be read by the `ijtiff` package, the number of slices OR the",
              "number of frames should be specified in the ImageDescription",
              "and they're interpreted as the same thing. It does not make",
              "sense for them to be different numbers."
            )
          )
        )
      }
    }
    n_slices <- n_frames
  }
  n_slices
}

#' Extract info from an ImageJ-style `ImageDescription`.
#'
#' @inheritParams prep_read
#'
#' @return A named list with elements `n_imgs`, `n_slices`, `ij_n_ch`, `n_ch`.
#'
#' @noRd
translate_ij_description <- function(tags1) {
  n_imgs <- NA_integer_
  n_slices <- NA_integer_
  ij_n_ch <- FALSE
  n_ch <- tags1$SamplesPerPixel %||% 1
  if ("ImageDescription" %in% names(tags1) &&
    !is.null(tags1$ImageDescription) &&
    startsWith(tags1$ImageDescription, "ImageJ")) {
    ij_description <- tags1$ImageDescription
    if (stringr::str_detect(ij_description, "channels=")) {
      n_ch <- strex::str_first_number_after_first(
        ij_description,
        "channels="
      )
      ij_n_ch <- TRUE
    }
    n_imgs <- strex::str_first_number_after_first(ij_description, "images=")
    n_slices <- calculate_n_slices(ij_description)
    if ((!is.na(n_slices) && !is.na(n_imgs)) &&
      ij_n_ch &&
      n_imgs != n_ch * n_slices) {
      rlang::abort(
        c(
          stringr::str_glue(
            "The ImageJ-written image you're trying to read says in its ",
            "ImageDescription that it has {n_imgs} images of ",
            "{n_slices} slices of {n_ch} channels. However, with {n_slices} ",
            "slices of {n_ch} channels, one would expect there to be ",
            "{n_slices} x {n_ch} = {n_ch * n_slices} images."
          ),
          x = paste(
            "This discrepancy means that the `ijtiff` package",
            "can't read your image correctly."
          ),
          i = paste(
            "One possible source of this kind of error is that your",
            "image may be temporal and volumetric. `ijtiff` can handle",
            "either time-based or volumetric stacks, but not both."
          )
        )
      )
    }
  }
  list(n_imgs = n_imgs, n_slices = n_slices, ij_n_ch = ij_n_ch, n_ch = n_ch)
}

#' Get information necessary for reading the image.
#'
#' While doing so, perform a check to see if the requested frames exist.
#'
#' @param path The path to the TIFF file.
#' @param frames An integerish vector. The requested frames.
#' @param tags1 The tags from the first image (directory) in the TIFF file. The
#'   first element of an output from [read_tags()].
#' @param tags Are we prepping the read of just tags (`TRUE`) or an image
#'   (`FALSE`).
#'
#' @return A list with seven elements.
#' * `frames` is the adjusted frame numbers (allowing for _ImageJ_  stuff),
#'  unique and sorted.
#' * `back_map` is a mapping from `frames` back to its non-unique, unsorted
#'  original; that would be `frames[back_map]`.
#'  * `n_ch` is the number of channels.
#'  * `n_dirs` is the number of directories in the TIFF image.
#'  * `n_slices` is the number of slices in the TIFF file. For most, this is the
#'   same as `n_dirs` but for ImageJ-written images it can be different.
#'  * `n_imgs` is the number of images according to the ImageJ
#'   `ImageDescription`. If not specified, it's `NA`.
#'  * `ij_n_ch` is `TRUE` if the number of channels was specified in the ImageJ
#'   `ImageDescription`, otherwise `FALSE`.
#'
#' @noRd
prep_read <- function(path, frames, tags1, tags = FALSE) {
  frames <- prep_frames(frames)
  frames_max <- max(frames)
  translated_ij_desc <- translate_ij_description(tags1)
  path <- fs::path_expand(path)
  n_dirs <- .Call("count_directories_C", path, PACKAGE = "ijtiff")
  if (!is.na(translated_ij_desc$n_slices)) {
    if (frames[[1]] == "all") {
      frames <- seq_len(translated_ij_desc$n_slices)
      frames_max <- translated_ij_desc$n_slices
    }
    if (frames_max > translated_ij_desc$n_slices) {
      rlang::abort(
        stringr::str_glue(
          "You have requested frame number {frames_max} but ",
          "there are only {translated_ij_desc$n_slices} frames in total."
        )
      )
    }
    if (translated_ij_desc$ij_n_ch) {
      if (n_dirs != translated_ij_desc$n_slices) {
        if (!is.na(translated_ij_desc$n_imgs) &&
          n_dirs != translated_ij_desc$n_imgs) {
          rlang::abort(
            c(
              paste(
                "If ImageDescription specifies the number of images, this",
                "must be equal to the number of directories in the TIFF file."
              ),
              x = stringr::str_glue("Your TIFF file has {n_dirs} directories."),
              x = stringr::str_glue(
                "Its ImageDescription indicates that it",
                " holds {translated_ij_desc$n_imgs} images."
              )
            )
          )
        }
        if (tags) {
          frames <- frames * translated_ij_desc$n_ch - (translated_ij_desc$n_ch - 1)
        } else {
          frames <- purrr::map(
            frames * translated_ij_desc$n_ch,
            ~ .x - rev((seq_len(translated_ij_desc$n_ch) - 1))
          ) %>%
            unlist()
        }
      }
    }
  } else {
    if (frames[[1]] == "all") {
      frames <- seq_len(n_dirs)
      frames_max <- n_dirs
    }
    if (frames_max > n_dirs) {
      rlang::abort(
        stringr::str_glue(
          "You have requested frame number {frames_max} but",
          " there are only {n_dirs} frames in total."
        )
      )
    }
  }
  good_frames <- sort(unique(frames))
  back_map <- match(frames, good_frames)
  list(
    frames = as.integer(good_frames),
    back_map = back_map,
    n_ch = translated_ij_desc$n_ch,
    n_dirs = n_dirs,
    n_slices = ifelse(is.na(translated_ij_desc$n_slices), n_dirs, translated_ij_desc$n_slices),
    n_imgs = translated_ij_desc$n_imgs,
    ij_n_ch = translated_ij_desc$ij_n_ch
  )
}

#' Check if EBImage is installed.
#'
#' Error if not.
#'
#' @return `TRUE` (invisibly) if installed.
#'
#' @noRd
ebimg_check <- function() {
  if (!rlang::is_installed("EBImage")) {
    stop(paste0(
      "To use this function, you need to have the `EBImage` package ",
      "installed.", "\n", ebimg_install_msg()
    ))
  }
  invisible(TRUE)
}

match_pillar_to_row_3 <- function(arr3d, mat) {
  checkmate::assert_array(arr3d, d = 3, mode = "double")
  checkmate::assert_matrix(mat, mode = "integer")
  .Call("match_pillar_to_row_3_C", arr3d, mat, PACKAGE = "ijtiff")
}
