# Copyright 2019 OpenCensus Authors
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


require_relative "../test_helper"

describe OpenCensus::Stats::Exporters::Stackdriver do
  let(:project_id) { "my-project" }
  let(:metric_prefix) { "test_metric_prefix" }
  let(:converter) {
    OpenCensus::Stats::Exporters::Stackdriver::Converter.new project_id
  }
  let(:metric_prefix) {
    "test_metric_prefix"
  }
  let(:resource_type) {
    "test_resource-type"
  }
  let(:resource_labels) {
    { "project_id" => project_id, "foo" => "bar" }
  }
  let(:measure1) {
    OpenCensus::Stats.create_measure_int name: "size_#{SecureRandom.hex(8)}", unit: "kb"
  }
  let(:measure2) {
    OpenCensus::Stats.create_measure_int name: "latency_#{SecureRandom.hex(8)}", unit: "ms"
  }
  let(:sum_aggr){
    OpenCensus::Stats.create_sum_aggregation
  }
  let(:last_value_aggr){
    OpenCensus::Stats.create_last_value_aggregation
  }
  let(:columns1){
    ["v1column1", "v1column2"]
  }
  let(:columns2){
    ["v2column1", "v2column2"]
  }
  let(:view1){
    OpenCensus::Stats::View.new(
      name: "size",
      measure: measure1,
      aggregation: sum_aggr,
      columns: columns1
    )
  }
  let(:view2){
    OpenCensus::Stats::View.new(
      name: "latency",
      measure: measure2,
      aggregation: last_value_aggr,
      columns: columns2
    )
  }

  describe "#export" do
    it "sends stats" do
      mock_client = Minitest::Mock.new
      # concurrent-ruby tests values against nil. Need to make sure the mock
      # responds appropriately.
      def mock_client.nil?; false; end

      view_data1 = OpenCensus::Stats::ViewData.new view1, start_time: Time.now.utc
      tags1 = columns1.each_with_object({}){| v, r| r[v] = "value#{v}"}
      measurement1 = view_data1.view.measure.create_measurement value: 5, tags: tags1
      view_data1.record measurement1

      view_data2 = OpenCensus::Stats::ViewData.new view2, start_time: Time.now.utc
      tags2 = columns2.each_with_object({}){| v, r| r[v] = "value#{v}"}
      measurement2 = view_data2.view.measure.create_measurement value: 5, tags: tags2
      view_data2.record measurement2

      expected_time_series_protos = [view_data1, view_data2].map do |view_data|
        converter.convert_time_series metric_prefix, resource_type,
                                      resource_labels, view_data
      end
      expected_time_series_protos.flatten!
      mock_client.expect :create_time_series, nil, [name: "projects/#{project_id}", time_series: expected_time_series_protos]

      exporter = OpenCensus::Stats::Exporters::Stackdriver.new(
        project_id: project_id,
        metric_prefix: metric_prefix,
        resource_type: resource_type,
        resource_labels: resource_labels,
        mock_client: mock_client
      )

      exporter.export [view_data1, view_data2]
      exporter.shutdown
      exporter.wait_for_termination(2)

      mock_client.verify
    end

    it "should not export an empty time series list" do
      mock_client = Minitest::Mock.new
      # concurrent-ruby tests values against nil. Need to make sure the mock
      # responds appropriately.
      def mock_client.nil?; false; end

      exporter = OpenCensus::Stats::Exporters::Stackdriver.new(
        project_id: project_id,
        metric_prefix: metric_prefix,
        resource_type: resource_type,
        resource_labels: resource_labels,
        mock_client: mock_client
      )

      # Since mock_client doesn't expect the batch_write_spans method to be
      # called, it should raise the NoMethodError if this happens
      exporter.export []

      exporter.shutdown
      exporter.wait_for_termination(2)

      mock_client.verify
    end
  end

  describe "#create_metric_descriptor" do
    it "create descriptor" do
      mock_client = Minitest::Mock.new
      # concurrent-ruby tests values against nil. Need to make sure the mock
      # responds appropriately.
      def mock_client.nil?; false; end

      exporter = OpenCensus::Stats::Exporters::Stackdriver.new(
        project_id: project_id,
        metric_prefix: metric_prefix,
        resource_type: resource_type,
        resource_labels: resource_labels,
        mock_client: mock_client
      )

      view = view1
      metric_descriptor = converter.convert_metric_descriptor view, metric_prefix
      metric_name = Google::Cloud::Monitoring::V3::MetricService::Paths.metric_descriptor_path(
        project: project_id,
        metric_descriptor: metric_descriptor.type
      )

      mock_client.expect :create_metric_descriptor, nil, [name: metric_name, metric_descriptor: metric_descriptor]

      exporter.create_metric_descriptor view
      exporter.shutdown
      exporter.wait_for_termination(2)

      mock_client.verify
    end

    it "raise an error for bad api response" do
      mock_client = Minitest::Mock.new
      # concurrent-ruby tests values against nil. Need to make sure the mock
      # responds appropriately.
      def mock_client.nil?; false; end

      exporter = OpenCensus::Stats::Exporters::Stackdriver.new(
        project_id: project_id,
        metric_prefix: metric_prefix,
        resource_type: resource_type,
        resource_labels: resource_labels,
        mock_client: mock_client
      )

      view = view1
      metric_descriptor = converter.convert_metric_descriptor view, metric_prefix
      metric_name = Google::Cloud::Monitoring::V3::MetricService::Paths.metric_descriptor_path(
        project: project_id,
        metric_descriptor: metric_descriptor.type
      )

      mock_client.expect :create_metric_descriptor, nil do |metric_name, metric_descriptor|
        raise "TEST ERROR - metric is alreay exists"
      end

      assert_raises StandardError do
        exporter.create_metric_descriptor view
      end

      exporter.shutdown
      exporter.wait_for_termination(2)

      mock_client.verify
    end
  end
end
