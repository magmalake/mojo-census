# mojo-census

## Pipeline docstrings

The orca UI shows the first paragraph of a pipeline's module docstring
(`pipelines/*.mojo`) prominently, as the pipeline's description. Keep that
paragraph a complete summary of what the pipeline does and when it runs: on a
schedule, as a sensor on a table, or by hand (a backfill, and what triggers
it). When a change alters what a pipeline records or when it should run,
update that first paragraph in the same PR, not only the paragraphs below it.
