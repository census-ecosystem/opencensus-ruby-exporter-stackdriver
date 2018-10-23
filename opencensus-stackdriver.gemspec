lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "opencensus/stackdriver/version"

Gem::Specification.new do |spec|
  spec.name =        "opencensus-stackdriver"
  spec.version =     OpenCensus::Stackdriver::VERSION
  spec.authors =     ["Daniel Azuma"]
  spec.email =       ["dazuma@google.com"]

  spec.summary =     "Stackdriver exporter for OpenCensus"
  spec.description = "Stackdriver exporter for OpenCensus"
  spec.homepage =    "https://github.com/census-instrumentation/ruby-stackdriver-exporter"
  spec.license =     "Apache-2.0"

  spec.files = ::Dir.glob("lib/**/*.rb") +
               ::Dir.glob("*.md") +
               ["AUTHORS", "LICENSE", ".yardopts"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.2.0"

  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "google-cloud-trace", "~> 0.33"
  spec.add_dependency "opencensus", "~> 0.4"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "faraday", "~> 0.13"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-focus", "~> 1.1"
  spec.add_development_dependency "rails", "~> 5.1.4"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rubocop", "~> 0.59.2"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "yard-doctest", "~> 0.1.6"
end
