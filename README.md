<p align="center">
<a href="https://hexdocs.pm/pravda/"><img src="https://img.shields.io/badge/api-docs-green" alt="Docs"/></a>
<a href="https://travis-ci.com/mogorman/pravda"><img src="https://travis-ci.com/mogorman/pravda.svg?branch=master" alt="Build"/></a>
<a href="https://coveralls.io/github/mogorman/pravda?branch=master"><img src="https://coveralls.io/repos/github/mogorman/pravda/badge.svg" alt="Code Coverage"/></a>
<a href="https://hex.pm/packages/pravda"><img src="http://img.shields.io/hexpm/v/pravda.svg" alt="Package"/></a>
<a href="COPYING.txt"><img src="http://img.shields.io/hexpm/l/pravda.svg" alt="License"/></a>
<img src="https://img.shields.io/hexpm/dt/pravda" alt="Downloads"/>
<img src="/pravda.png" alt="pravda logo"/>

# Pravda: An OpenAPI 3.0 validator plug for phoenix.
<!-- end_header -->
Pravda is a plug for phoenix to validate input and output against a provided spec.
It also supports having multiple versions of the same spec lodaded at one time, and the
ability to migrate the input version to the current spec, and downgrade the output to the
desired sepc. It supports custom error messages via callbacks, and extra logging via callback
as well.

Metrics are implemented via telemetry.

## Example
```elixir
    plug(Pravda, %{
      spec_var: "spec-version",
      all_paths_required: true,
      error_callback: MyApp.Utils.PravdaErrorLogger,
      migration_callback: MyApp.Utils.PravdaMigrations,
      specs: Pravda.Loader.read_dir("deps/my_specs/suppored_releases"),
    })
```

## Installation

Add the following to the `deps` block in `mix.exs`:

    {:pravda, "~>0.6.0"}

## Configuration

Configuration can be specified in the `opts` argument to all Pravda
functions, by setting config values with e.g., `Application.put_env`,
or by a combination of the two.

The following configuration options are supported:
* `:name` a namespace for all other options so you can have multiple instances of the plug. Default `Pravda.DefaultName`
* `:enable` enable or disable the plug entirely. Default `true`.
* `:specs` List of files to use for validation,
* `:spec_var` Name of the spec-var we are matching against. Default `"spec-var"`
* `:spec_var_placement` the location of the spec var. Options are `:query, :path, :header`  Default  `:header`
* `:migration_callback` Module to be passed in that will be called when the spec is attempted to migrate Default `nil`
* `:error_callback` Module to be passed in that will be called when there is an error in the input or output, Default: `nil`
* `:custom_error_callback` Module to be passed in that will provide enduser with a custom error message, Default: `nil`
* `:all_paths_required` The path passed into the plug must match one of its rules if true, Default: `:true`
* `:explain_error` provide the reason validation failed, Default: `true`
* `:validate_params` validate input params, header, path, query, Default: `true`
* `:validate_body` validate input body from user, Default: `true`
* `:validate_response` validate output response to the user, Default: `true`
* `:allow_invalid_input` allow input to pass even if it fails validation, Default: `false`
* `:allow_invalid_output` allow output to pass even if it fails validation, Default: `false`
* `:migrate_input` migrate input from current spec to latest input spec, Default: `true`
* `:migrate_output` migrate output from current spec to client requested spec, Default: `true`

# TODO
* `:fallback_to_latest` migrate output to latest if true, otherwise fallback to oldest supported version, Default: `true`

## Metrics

Metrics are offered via the [Telemetry
library](https://github.com/beam-telemetry/telemetry). The following
metrics are emitted:
* `[:pravda, :request, :params, :valid]` Successfully validated input parameters
* `[:pravda, :request, :params, :invalid]` Input parameters failed to validate
* `[:pravda, :request, :body, :valid]` Successfully validated body
* `[:pravda, :request, :body, :invalid]` Input body failed to validate
* `[:pravda, :request, :response, :valid]` Successfully validated output response
* `[:pravda, :request, :response, :invalid]` Output response failed to validate
* `[:pravda, :request, :migrate, :up]` Successfully migrated input spec up
* `[:pravda, :request, :migrate, :down]` Successfully migrated output spec down
* `[:pravda, :request, :complete]`  Request made it through the plug
* `[:pravda, :request, :start]`  Request made it into the plug

## Contributing

Thanks for considering contributing to this project, and to the free
software ecosystem at large!

Interested in contributing a bug report?  Terrific!  Please open a [GitHub
issue](https://github.com/mogorman/pravda/issues) and include as much detail
as you can.  If you have a solution, even better -- please open a pull
request with a clear description and tests.

Have a feature idea?  Excellent!  Please open a [GitHub
issue](https://github.com/mogorman/pravda/issues) for discussion.

Want to implement an issue that's been discussed?  Fantastic!  Please
open a [GitHub pull request](https://github.com/mogorman/pravda/pulls)
and write a clear description of the patch.
We'll merge your PR a lot sooner if it is well-documented and fully
tested.

## Authorship and License

Copyright 2020, Matthew O'Gorman.

This software is released under the MIT License.
