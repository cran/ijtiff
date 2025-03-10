## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  crop = TRUE
)
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)

## ----supported-tags-----------------------------------------------------------
library(ijtiff)
print(supported_tags <- get_supported_tags())

## ----read-tags-example--------------------------------------------------------
sample_tiff <- system.file("img", "Rlogo.tif", package = "ijtiff")
tags <- read_tags(sample_tiff)
tags[[1]]

## ----tag-examples-------------------------------------------------------------
tags[[1]]$ImageWidth
tags[[1]]$ImageLength # Height of the image
tags[[1]]$XResolution
tags[[1]]$YResolution
tags[[1]]$ResolutionUnit

## ----multi-frame-tags, message=FALSE------------------------------------------
multi_frame_tiff <- system.file("img", "Rlogo-banana.tif", package = "ijtiff")
multi_frame_tags <- read_tags(multi_frame_tiff)
length(multi_frame_tags)

## ----compare-tags-------------------------------------------------------------
dimensions <- data.frame(
  Frame = character(),
  Width = integer(),
  Height = integer(),
  stringsAsFactors = FALSE
)
for (i in seq_along(multi_frame_tags)) {
  frame_name <- names(multi_frame_tags)[i]
  dimensions <- rbind(
    dimensions,
    data.frame(
      Frame = frame_name,
      Width = multi_frame_tags[[i]]$ImageWidth,
      Height = multi_frame_tags[[i]]$ImageLength,
      stringsAsFactors = FALSE
    )
  )
}
dimensions

