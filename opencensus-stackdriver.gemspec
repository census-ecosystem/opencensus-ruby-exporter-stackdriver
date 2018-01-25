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

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "opencensus", "~> 0.1.0"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "faraday", "~> 0.13"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rails", "~> 5.1.4"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rubocop", "~> 0.52"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "yard-doctest", "~> 0.1.6"
end
