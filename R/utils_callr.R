callr_outer <- function(
  targets_function,
  targets_arguments,
  callr_function,
  callr_arguments,
  envir,
  script,
  store,
  fun
) {
  tar_assert_scalar(store)
  tar_assert_chr(store)
  tar_assert_nzchar(store)
  tar_assert_script(script)
  out <- callr_dispatch(
    targets_function = targets_function,
    targets_arguments = targets_arguments,
    callr_function = callr_function,
    callr_arguments = callr_arguments,
    envir = envir,
    script = script,
    store = store,
    fun = fun
  )
  if_any(
    inherits(out, "error"),
    callr_error(condition = out, fun = fun),
    out
  )
}

callr_error <- function(condition, fun) {
  message <- sprintf(
    paste0(
      "Error running targets::%s()\n",
      "  Error messages: ",
      "targets::tar_meta(fields = error, complete_only = TRUE)\n",
      "  Debugging guide: https://books.ropensci.org/targets/debugging.html\n",
      "  How to ask for help: https://books.ropensci.org/targets/help.html\n",
      "  Last error: %s"
    ),
    fun,
    conditionMessage(condition)
  )
  tar_throw_run(message, class = class(condition))
}

callr_dispatch <- function(
  targets_function,
  targets_arguments,
  callr_function,
  callr_arguments,
  envir,
  script,
  store,
  fun
) {
  options <- list(crayon.enabled = interactive())
  callr_arguments$func <- callr_inner
  callr_arguments$args <- list(
    targets_function = targets_function,
    targets_arguments = targets_arguments,
    options = options,
    script = script,
    store = store,
    fun = fun
  )
  if_any(
    is.null(callr_function),
    callr_inner(
      targets_function = targets_function,
      targets_arguments = targets_arguments,
      options = options,
      envir = envir,
      script = script,
      store = store,
      fun = fun
    ),
    do.call(
      callr_function,
      callr_prepare_arguments(callr_function, callr_arguments)
    )
  )
}

callr_inner <- function(
  targets_function,
  targets_arguments,
  options,
  envir = NULL,
  script,
  store,
  fun
) {
  force(envir)
  parent <- parent.frame()
  tryCatch(
    targets::tar_callr_inner_try(
      targets_function = targets_function,
      targets_arguments = targets_arguments,
      options = options,
      envir = envir,
      parent = parent,
      script = script,
      store = store,
      fun = fun
    ),
    error = function(condition) condition
  )
}

#' @title Invoke a `targets` task from inside a `callr` function.
#' @export
#' @keywords internal
#' @description Not a user-side function. Do not invoke directly.
#'   Exported for internal purposes only.
#' @return The output of a call to a `targets` function that uses
#'   `callr` for reproducibility.
#' @inheritParams tar_validate
#' @param targets_function A function from `targets` to call.
#' @param targets_arguments Named list of arguments of targets_function.
#' @param options Names of global options to temporarily set
#'   in the `callr` process.
#' @param envir Name of the environment to run in. If `NULL`,
#'   the environment defaults to `tar_option_get("envir")`.
#' @param parent Parent environment of the call to
#'   `tar_call_inner()`.
#' @param fun Character of length 1, name of the `targets`
#'   function being called.
#' @examples
#' # See the examples of tar_make().
tar_callr_inner_try <- function(
  targets_function,
  targets_arguments,
  options,
  envir = NULL,
  parent,
  script,
  store,
  fun
) {
  if (is.null(envir)) {
    envir <- parent
  }
  old_envir <- targets::tar_option_get("envir")
  targets::tar_option_set(envir = envir)
  targets::tar_runtime_object()$set_script(script)
  targets::tar_runtime_object()$set_store(store)
  targets::tar_runtime_object()$set_fun(fun)
  on.exit(targets::tar_option_set(envir = old_envir))
  on.exit(targets::tar_runtime_object()$unset_script(), add = TRUE)
  on.exit(targets::tar_runtime_object()$unset_store(), add = TRUE)
  on.exit(targets::tar_runtime_object()$unset_fun(), add = TRUE)
  withr::local_options(options)
  targets <- eval(parse(text = readLines(script, warn = FALSE)), envir = envir)
  targets_arguments$pipeline <- targets::tar_as_pipeline(targets)
  targets::tar_pipeline_validate_lite(targets_arguments$pipeline)
  do.call(targets_function, targets_arguments)
}

callr_prepare_arguments <- function(callr_function, callr_arguments) {
  if ("show" %in% names(formals(callr_function))) {
    callr_arguments$show <- callr_arguments$show %||% TRUE
  }
  if ("env" %in% names(formals(callr_function))) {
    callr_arguments$env <- callr_arguments$env %||% callr::rcmd_safe_env()
    callr_arguments$env <- c(
      callr_arguments$env,
      PROCESSX_NOTIFY_OLD_SIGCHLD = "true"
    )
  }
  callr_arguments
}

#' @title Default `callr` arguments.
#' @export
#' @keywords internal
#' @description Default `callr` arguments for the `callr_arguments`
#'   argument of [tar_make()] and related functions.
#' @details Not a user-side function. Do not invoke directly.
#'   Exported for internal purposes only.
#' @return A list of arguments to `callr_function`.
#' @param callr_function A function from the `callr` package
#'   that starts an external R process.
#' @param reporter Character of length 1, choice of reporter
#'   for [tar_make()] or a related function.
#' @examples
#' tar_callr_args_default(callr::r)
tar_callr_args_default <- function(callr_function, reporter = NULL) {
  if (is.null(callr_function)) {
    return(list())
  }
  out <- list(spinner = !identical(reporter, "summary"))
  out[intersect(names(out), names(formals(callr_function)))]
}

#' @title Deprecated: `callr` arguments.
#' @export
#' @keywords internal
#' @description Deprecated on 2022-08-05 (version 0.13.1).
#'   Please use [tar_callr_args_default()] instead.
#' @details Not a user-side function. Do not invoke directly.
#'   Exported for internal purposes only.
#' @return A list of arguments to `callr_function`.
#' @param callr_function A function from the `callr` package
#'   that starts an external R process.
#' @param reporter Character of length 1, choice of reporter
#'   for [tar_make()] or a related function.
#' @examples
#' tar_callr_args_default(callr::r)
callr_args_default <- function(callr_function, reporter = NULL) {
  msg <- paste(
    "callr_args_default() is deprecated in {targets}.",
    "please use tar_callr_args_default() instead"
  )
  cli_red_x(msg)
  tar_callr_args_default(
    callr_function = callr_function,
    reporter = reporter
  )
}
