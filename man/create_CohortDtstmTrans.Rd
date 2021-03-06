% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dtstm.R
\name{create_CohortDtstmTrans}
\alias{create_CohortDtstmTrans}
\alias{create_CohortDtstmTrans.multinom_list}
\alias{create_CohortDtstmTrans.msm}
\title{Create \code{CohortDtstmTrans} object}
\usage{
create_CohortDtstmTrans(object, ...)

\method{create_CohortDtstmTrans}{multinom_list}(
  object,
  input_data,
  trans_mat,
  n = 1000,
  uncertainty = c("normal", "none"),
  ...
)

\method{create_CohortDtstmTrans}{msm}(
  object,
  input_data,
  cycle_length,
  n = 1000,
  uncertainty = c("normal", "none"),
  ...
)
}
\arguments{
\item{object}{An object of the appropriate class.}

\item{...}{Further arguments passed to or from other methods. Currently unused.}

\item{input_data}{An object of class \code{expanded_hesim_data} returned by
\code{\link[=expand.hesim_data]{expand.hesim_data()}}}

\item{trans_mat}{A transition matrix describing the states and transitions
in a discrete-time multi-state model. See \code{\link{CohortDtstmTrans}}.}

\item{n}{Number of random observations of the parameters to draw.}

\item{uncertainty}{Method determining how parameter uncertainty should be handled. See
documentation in \code{\link[=create_params]{create_params()}}.}

\item{cycle_length}{The length of a model cycle in terms of years. The default
is 1 meaning that model cycles are 1 year long.}
}
\description{
A generic function for creating an object of class \code{CohortDtstmTrans}.
}
\seealso{
\code{\link{CohortDtstmTrans}}
}
