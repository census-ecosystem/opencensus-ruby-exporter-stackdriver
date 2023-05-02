> **Warning**
>
> OpenCensus and OpenTracing have merged to form [OpenTelemetry](https://opentelemetry.io), which serves as the next major version of OpenCensus and OpenTracing.
>
> OpenTelemetry has now reached feature parity with OpenCensus, with tracing and metrics SDKs available in .NET, Golang, Java, NodeJS, and Python. **All OpenCensus Github repositories, except [census-instrumentation/opencensus-python](https://github.com/census-instrumentation/opencensus-python), will be archived on July 31st, 2023**. We encourage users to migrate to OpenTelemetry by this date.
>
> To help you gradually migrate your instrumentation to OpenTelemetry, bridges are available in Java, Go, Python, and JS. [**Read the full blog post to learn more**](https://opentelemetry.io/blog/2023/sunsetting-opencensus/).

# Ruby Stackdriver Exporter for OpenCensus

This repository contains the source to the `opencensus-stackdriver` gem. This
library is a plugin for
[Ruby OpenCensus](https://github.com/census-instrumentation/opencensus-ruby)
that exports data to [Stackdriver](https://cloud.google.com/stackdriver/).

OpenCensus is a platform- and provider-agnostic framework for distributed
tracing and stats collection. For more information, see https://opencensus.io.

This library is in an alpha stage, and the API is subject to change. In
particular, support for the Stats API is currently incomplete and experimental.

## Quick Start

### Installation

Install the gem using Bundler:

1. Add the `opencensus-stackdriver` gem to your application's Gemfile:

```ruby
gem "opencensus-stackdriver"
```

2. Use Bundler to install the gem:

```sh
$ bundle install
```

The core `opencensus` gem and the `google-cloud-trace` client library for the
Stackdriver API will be installed automatically as dependencies.

### Installing the plugin

The Stackdriver plugin can be installed using OpenCensus configuration.
Insert the following code in your application's initialization:

```ruby
OpenCensus.configure do |c|
  c.trace.exporter = OpenCensus::Trace::Exporters::Stackdriver.new
end
```

If you are using **Ruby on Rails**, you can equivalently include this code in
your Rails config:

```ruby
config.opencensus.trace.exporter = OpenCensus::Trace::Exporters::Stackdriver.new
```

See the documentation for
[OpenCensus::Trace::Exporters::Stackdriver](http://www.rubydoc.info/gems/opencensus-stackdriver/OpenCensus/Trace/Exporters/Stackdriver)
for information on the configuration options for the Stackdriver exporter.

You can find more general information on using OpenCensus from Ruby, including
configuring automatic trace capture and adding custom spans, in the
[core `opencensus` README](https://github.com/census-instrumentation/opencensus-ruby).

### Connecting to Stackdriver

If you do not have a Google Cloud project, create one from the
[cloud console](https://console.cloud.google.com/).

The Stackdriver plugin needs credentials for your project in order to export
traces to the Stackdriver backend. If your application is running in Google
Cloud Platform hosting (i.e.
[Google App Engine](https://cloud.google.com/appengine/),
[Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/), or
[Google Compute Engine](https://cloud.google.com/compute/)), then the plugin
can generally retrieve the needed credentials automatically from the runtime
environment. See
[this section](https://github.com/GoogleCloudPlatform/google-cloud-ruby/tree/master/google-cloud-trace#running-on-google-cloud-platform)
from the `google-cloud-trace` README for details.

If you are running the application locally, in self-hosted VMs, or a third
party hosting service, you will need to provide the project ID and credentials
(keyfile) to the Google Cloud client library. See
[this section](https://github.com/GoogleCloudPlatform/google-cloud-ruby/tree/master/google-cloud-trace#running-locally-and-elsewhere)
for details.

Either way, once you have the Stackdriver exporter configured, you can view
traces on the [Google Cloud Console](https://console.cloud.google.com/traces).

## About the library

### Supported Ruby Versions

This library is supported on Ruby 2.2+.

However, Ruby 2.3 or later is strongly recommended, as earlier releases have
reached or are nearing end-of-life. After June 1, 2018, OpenCensus will provide
official support only for Ruby versions that are considered current and
supported by Ruby Core (that is, Ruby versions that are either in normal
maintenance or in security maintenance).
See https://www.ruby-lang.org/en/downloads/branches/ for further details.

### Versioning

This library follows [Semantic Versioning](http://semver.org/).

It is currently in major version zero (0.y.z), which means that anything may
change at any time, and the public API should not be considered stable.

## Contributing

Contributions to this library are always welcome and highly encouraged.

See the [Contributing Guide](CONTRIBUTING.md) for more information on how to get
started.

Please note that this project is released with a Contributor Code of Conduct. By
participating in this project you agree to abide by its terms. See
[Code of Conduct](CODE_OF_CONDUCT.md) for more information.

## License

This library is licensed under Apache 2.0. Full license text is available in
[LICENSE](LICENSE).
