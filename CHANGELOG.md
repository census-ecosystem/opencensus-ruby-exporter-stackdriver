# Release History

### 0.2.0 / Unreleased

This release requires version 0.4 or later of the opencensus gem.

* Map standard HTTP attributes from OpenCensus names to Stackdriver names.
* Fixed thread pool size configuration.

### 0.1.2 / 2018-05-22

* Add agent identifier and version attribute to reported spans.

### 0.1.1 / 2018-04-13

* Clean unneeded files from the gem
* Do not issue a write request for an empty span list (bogdanap)

### 0.1.0 / 2018-03-09

Initial release of the stackdriver export library
