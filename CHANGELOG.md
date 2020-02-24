# Release History

### 0.3.2 / 2020-02-24

* Update the google-cloud-trace and google-cloud-monitoring dependencies to versions that support service address override.

### 0.3.1 / 2020-02-06

* Support customizing the stackdriver service address

### 0.3.0 / 2019-10-14

This release requires version 0.5 or later of the opencensus gem. It includes
experimental support for exporting OpenCensus Stats to the Stackdriver
Monitoring service. Note that Stats support is incomplete and there are known
issues.

### 0.2.0 / 2018-10-22

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
