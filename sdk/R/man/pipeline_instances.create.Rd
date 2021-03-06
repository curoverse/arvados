% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Arvados.R
\name{pipeline_instances.create}
\alias{pipeline_instances.create}
\title{pipeline_instances.create}
\usage{
arv$pipeline_instances.create(pipelineinstance,
	ensure_unique_name = "false")
}
\arguments{
\item{pipelineInstance}{PipelineInstance object.}

\item{ensure_unique_name}{Adjust name to ensure uniqueness instead of returning an error on (owner_uuid, name) collision.}
}
\value{
PipelineInstance object.
}
\description{
pipeline_instances.create is a method defined in Arvados class.
}
