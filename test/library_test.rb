# Copyright 2018 OpenCensus Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "test_helper"

describe OpenCensus::Stackdriver do
  it "has a version number" do
    refute_nil ::OpenCensus::Stackdriver::VERSION
  end

  it "export traces to stackdriver sevice" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]
    exporter = OpenCensus::Trace::Exporters::Stackdriver.new
    OpenCensus::Trace.configure do |config|
      config.exporter = exporter
      config.default_sampler = OpenCensus::Trace::Samplers::AlwaysSample.new
    end
    OpenCensus::Trace.start_request_trace do |root_context|
      OpenCensus::Trace.in_span("span1") do |span1|
        span1.put_attribute :data, "Outer span"
        sleep 0.1
        OpenCensus::Trace.in_span("span2") do |span2|
          span2.put_attribute :data, "Inner span"
          sleep 0.2
        end
        OpenCensus::Trace.in_span("span3") do |span3|
          span3.put_attribute :data, "Another inner span"
          sleep 0.1
        end
      end
      exporter.export root_context.build_contained_spans
    end
    OpenCensus::Trace.start_request_trace do |root_context|
      OpenCensus::Trace.in_span("span4") do |span4|
        span4.put_attribute :data, "Fast span"
      end
      exporter.export root_context.build_contained_spans
    end
  end

  it "create a metric descriptor" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]

    exporter = OpenCensus::Stats::Exporters::Stackdriver.new(
      metric_prefix: "test.stackdriver.exporter",
      resource_type: "stackdriver_stats_tests"
    )

    measure = OpenCensus::Stats.create_measure_int name: "size_#{SecureRandom.hex(8)}", unit: "kb"
    sum_aggr = OpenCensus::Stats.create_sum_aggregation
    columns = ["column1", "column2"]
    view = OpenCensus::Stats::View.new(
      name: "test_sd_exporter_#{SecureRandom.hex(4)}",
      measure: measure,
      aggregation: sum_aggr,
      columns: columns
    )

    metric_descriptor = exporter.create_metric_descriptor view

    client_promise = exporter.instance_variable_get("@client_promise")
    client_promise.execute
    descriptor_delete_promise = client_promise.then do |client|
      client.delete_metric_descriptor(metric_descriptor.name)
    end

    descriptor_delete_promise.value!
  end

  it "record sum stats and export" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]

    exporter = OpenCensus::Stats::Exporters::Stackdriver.new
    OpenCensus::Stats.configure do |config|
      config.exporter = exporter
    end
    measure = OpenCensus::Stats.create_measure_int(
      name: "test_sd_exporter_sum_size",
      unit: "kb"
    )
    view = OpenCensus::Stats::View.new(
      name: "testview_sum",
      measure: measure,
      aggregation: OpenCensus::Stats.create_sum_aggregation,
      columns: ["frontend"]
    )

    recorder = OpenCensus::Stats.ensure_recorder
    recorder.register_view(view)
    exporter.create_metric_descriptor view

    measurement = measure.create_measurement value: 10, tags: {"frontend" => "mobile"}
    recorder.record measurement
    exporter.export recorder.views_data

    OpenCensus::Stats.unset_recorder_context
  end

  it "record last value stats and export" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]

    exporter = OpenCensus::Stats::Exporters::Stackdriver.new
    OpenCensus::Stats.configure do |config|
      config.exporter = exporter
    end
    measure = OpenCensus::Stats.create_measure_int(
      name: "test_sd_exporter_last_value_size",
      unit: "kb"
    )
    view = OpenCensus::Stats::View.new(
      name: "testview_last_value",
      measure: measure,
      aggregation: OpenCensus::Stats.create_last_value_aggregation,
      columns: ["frontend"]
    )

    recorder = OpenCensus::Stats.ensure_recorder
    recorder.register_view(view)
    exporter.create_metric_descriptor view

    measurement = measure.create_measurement value: 15, tags: {"frontend" => "mobile"}
    recorder.record measurement
    exporter.export recorder.views_data

    OpenCensus::Stats.unset_recorder_context
  end

  it "record count stats and export" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]

    exporter = OpenCensus::Stats::Exporters::Stackdriver.new
    OpenCensus::Stats.configure do |config|
      config.exporter = exporter
    end
    measure = OpenCensus::Stats.create_measure_int(
      name: "test_sd_exporter_count_size",
      unit: "1"
    )
    view = OpenCensus::Stats::View.new(
      name: "testview_count",
      measure: measure,
      aggregation: OpenCensus::Stats.create_count_aggregation,
      columns: ["frontend"]
    )

    recorder = OpenCensus::Stats.ensure_recorder
    recorder.register_view(view)
    exporter.create_metric_descriptor view

    measurement = measure.create_measurement value: 1, tags: {"frontend" => "mobile"}
    recorder.record measurement
    exporter.export recorder.views_data

    OpenCensus::Stats.unset_recorder_context
  end

  it "record distribution stats and export" do
    skip unless ENV["GOOGLE_CLOUD_PROJECT"]

    exporter = OpenCensus::Stats::Exporters::Stackdriver.new
    OpenCensus::Stats.configure do |config|
      config.exporter = exporter
    end
    measure = OpenCensus::Stats.create_measure_int(
      name: "test_sd_exporter_distribution_size",
      unit: "1"
    )
    view = OpenCensus::Stats::View.new(
      name: "testview_distribution",
      measure: measure,
      aggregation: OpenCensus::Stats.create_distribution_aggregation([1,5,10]),
      columns: ["frontend"]
    )

    recorder = OpenCensus::Stats.ensure_recorder
    recorder.register_view(view)
    exporter.create_metric_descriptor view

    measurement = measure.create_measurement value: 5, tags: {"frontend" => "mobile"}
    recorder.record measurement
    exporter.export recorder.views_data

    OpenCensus::Stats.unset_recorder_context
  end
end
