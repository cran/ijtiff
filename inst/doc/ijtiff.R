## ----cleanup, include = FALSE--------------------------------------------
new_files <- setdiff(dir(), original_files)
if (length(new_files)) file.remove(new_files)

