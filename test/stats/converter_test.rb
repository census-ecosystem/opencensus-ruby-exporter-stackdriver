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

describe OpenCensus::Stats::Exporters::Stackdriver::Converter do
  let(:project_id) { "my-project" }
  let(:converter) {
    OpenCensus::Stats::Exporters::Stackdriver::Converter.new project_id
  }
  let(:metric_prefix) {
    "test_metric_prefix"
  }
  let(:unit){
    "kb"
  }
  let(:measure_int) {
    OpenCensus::Stats.create_measure_int name: "int_#{SecureRandom.hex(8)}", unit: unit
  }
  let(:measure_double) {
    OpenCensus::Stats.create_measure_double name: "double_#{SecureRandom.hex(8)}", unit: unit
  }
  let(:count_aggr){
    OpenCensus::Stats.create_count_aggregation
  }
  let(:sum_aggr){
    OpenCensus::Stats.create_sum_aggregation
  }
  let(:last_value_aggr){
    OpenCensus::Stats.create_last_value_aggregation
  }
  let(:distribution_aggr){
    OpenCensus::Stats.create_distribution_aggregation [5, 10, 15]
  }
  let(:view_columns) {
    ["column1", "column2"]
  }
  let(:tags){
    { "column1" => "test1", "column2" => "test2"}
  }
  let(:view){
    OpenCensus::Stats::View.new(
      name: "testview",
      measure: measure_double,
      aggregation: last_value_aggr,
      columns: view_columns
    )
  }
  let(:count_aggr_data){
    count_aggr.create_aggregation_data
  }
  let(:sum_aggr_data){
    sum_aggr.create_aggregation_data
  }
  let(:last_value_aggr_data){
    last_value_aggr.create_aggregation_data
  }
  let(:distribution_aggr_data){
    distribution_aggr.create_aggregation_data
  }
  let(:last_value_view_double) {
    OpenCensus::Stats::View.new(
      name: "last_value.#{SecureRandom.hex(8)}",
      measure: measure_double,
      aggregation: last_value_aggr,
      columns: view_columns
    )
  }
  let(:last_value_view_int) {
    OpenCensus::Stats::View.new(
      name: "last_value.#{SecureRandom.hex(8)}",
      measure: measure_int,
      aggregation: last_value_aggr,
      columns: view_columns
    )
  }
  let(:count_view) {
    OpenCensus::Stats::View.new(
      name: "count.#{SecureRandom.hex(8)}",
      measure: measure_int,
      aggregation: count_aggr,
      columns: view_columns
    )
  }
  let(:sum_view_int) {
    OpenCensus::Stats::View.new(
      name: "sum.#{SecureRandom.hex(8)}",
      measure: measure_int,
      aggregation: sum_aggr,
      columns: view_columns
    )
  }
  let(:sum_view_double) {
    OpenCensus::Stats::View.new(
      name: "sum.#{SecureRandom.hex(8)}",
      measure: measure_double,
      aggregation: sum_aggr,
      columns: view_columns
    )
  }
  let(:distribution_view) {
    OpenCensus::Stats::View.new(
      name: "distribution.#{SecureRandom.hex(8)}",
      measure: measure_double,
      aggregation: distribution_aggr,
      columns: view_columns
    )
  }

  describe "#convert_metric_value_type" do
    it "converts for distribution aggregation" do
      value_type = converter.convert_metric_value_type distribution_view
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::DISTRIBUTION
    end

    it "converts for count aggregation" do
      value_type = converter.convert_metric_value_type count_view
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::INT64
    end

    it "converts for sum aggregation with int measure" do
      value_type = converter.convert_metric_value_type sum_view_int
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::INT64
    end

    it "converts for sum aggregation with double measure" do
      value_type = converter.convert_metric_value_type sum_view_double
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::DOUBLE
    end

    it "converts for last value aggregation with int measure" do
      value_type = converter.convert_metric_value_type last_value_view_int
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::INT64
    end

    it "converts for last value aggregation with double measure" do
      value_type = converter.convert_metric_value_type last_value_view_double
      value_type.must_equal Google::Api::MetricDescriptor::ValueType::DOUBLE
    end
  end

  describe "#convert_metric_kind" do
    it "converts for last value aggregation" do
      metric_kind = converter.convert_metric_kind last_value_aggr
      metric_kind.must_equal Google::Api::MetricDescriptor::MetricKind::GAUGE
    end

    it "converts for distribution aggregation" do
      metric_kind = converter.convert_metric_kind distribution_aggr
      metric_kind.must_equal Google::Api::MetricDescriptor::MetricKind::CUMULATIVE
    end

    it "converts for sum aggregation" do
      metric_kind = converter.convert_metric_kind sum_aggr
      metric_kind.must_equal Google::Api::MetricDescriptor::MetricKind::CUMULATIVE
    end

    it "converts for count aggregation" do
      metric_kind = converter.convert_metric_kind count_aggr
      metric_kind.must_equal Google::Api::MetricDescriptor::MetricKind::CUMULATIVE
    end
  end

  describe "#make_metric_type" do
    it "build metric type" do
      path = converter.make_metric_type metric_prefix, "testname"
      path.must_equal "#{metric_prefix}/testname"
    end
  end

  describe "#convert_metric_descriptor" do
    it "converts for distribution aggregation" do
      descriptor = converter.convert_metric_descriptor view, metric_prefix
      descriptor.type.must_equal "#{metric_prefix}/#{view.name}"
      descriptor.display_name.must_equal view.measure.name
      descriptor.metric_kind.must_equal :GAUGE
      descriptor.value_type.must_equal :DOUBLE
      descriptor.unit.must_equal unit

      descriptor.labels.each_with_index do |label, index|
        label.key.must_equal view_columns[index]
        label.value_type.must_equal :STRING
      end
    end
  end

  describe "#create_distribution_point" do
    it "create a point object" do
      start_time = Time.now.utc - 100
      end_time = Time.now.utc

      aggr_data = distribution_aggr_data
      aggr_data.add 1, end_time

      point = converter.create_distribution_point(
        start_time,
        end_time,
        distribution_aggr_data
      )

      point.interval.start_time.to_time.must_equal start_time
      point.interval.end_time.to_time.must_equal end_time

      distribution_value = point.value.distribution_value
      distribution_value.count.must_equal 1
      distribution_value.mean.must_equal 1
      distribution_value.sum_of_squared_deviation.must_equal 0
      distribution_value.bucket_counts.must_equal [0, 1, 0, 0, 0]
      distribution_value.bucket_options.explicit_buckets.bounds.must_equal [0, 5, 10, 15]
    end
  end

  describe "#create_number_point" do
    it "create a point object with int64 type " do
      start_time = Time.now.utc - 100
      end_time = Time.now.utc

      point = converter.create_number_point start_time, end_time, 100, measure_int

      point.interval.start_time.to_time.must_equal start_time
      point.interval.end_time.to_time.must_equal end_time
      point.value.int64_value.must_equal 100
    end

    it "create a point object with double type" do
      start_time = Time.now.utc - 100
      end_time = Time.now.utc

      point = converter.create_number_point start_time, end_time, 10.1, measure_double

      point.interval.start_time.to_time.must_equal start_time
      point.interval.end_time.to_time.must_equal end_time
      point.value.double_value.must_equal 10.1
    end
  end

  describe "#convert_point" do
    it "converts last value aggregation data to point" do
      view = last_value_view_double
      view_data = OpenCensus::Stats::ViewData.new view, start_time: Time.now.utc

      measurement = view.measure.create_measurement value: 10.0, tags: tags
      view_data.record measurement
      aggr_data = view_data.data.values.first

      point = converter.convert_point view_data.start_time, aggr_data.time, view.measure, aggr_data
      point.interval.start_time.must_equal point.interval.end_time
      point.value.double_value.must_equal 10.0
    end

    it "converts count aggregation data to point" do
      view = count_view
      view_data = OpenCensus::Stats::ViewData.new view, start_time: (Time.now.utc - 100)

      measurement = view.measure.create_measurement value: 10.0, tags: tags
      view_data.record measurement
      aggr_data = view_data.data.values.first

      point = converter.convert_point view_data.start_time, aggr_data.time, view.measure, aggr_data
      point.interval.end_time.to_time.must_be :>, point.interval.start_time.to_time
      point.value.int64_value.wont_be_nil
    end

    it "converts sum aggregation data to point" do
      view = sum_view_int
      view_data = OpenCensus::Stats::ViewData.new view, start_time: (Time.now.utc - 100)

      measurement = view.measure.create_measurement value: 10, tags: tags
      view_data.record measurement
      aggr_data = view_data.data.values.first

      point = converter.convert_point view_data.start_time, aggr_data.time, view.measure, aggr_data
      point.interval.end_time.to_time.must_be :>, point.interval.start_time.to_time
      point.value.int64_value.wont_be_nil
    end

    it "converts distribution aggregation data to point" do
      view = distribution_view
      view_data = OpenCensus::Stats::ViewData.new view, start_time: (Time.now.utc - 100)

      measurement = view.measure.create_measurement value: 10, tags: tags
      view_data.record measurement
      aggr_data = view_data.data.values.first

      point = converter.convert_point view_data.start_time, aggr_data.time, view.measure, aggr_data
      point.interval.end_time.to_time.must_be :>, point.interval.start_time.to_time
      point.value.distribution_value.wont_be_nil
    end
  end

  describe "#convert_time_series" do
    it "convert aggregated views data to time series object" do
      view = last_value_view_double
      view_data = OpenCensus::Stats::ViewData.new view, start_time: Time.now.utc
      measurement = view.measure.create_measurement value: 10.0, tags: tags
      view_data.record measurement

      metric_prefix = "test-resource"
      resource_type = "test-resource"
      resource_labels = { "project_id" => project_id, "foo" => "bar" }
      series_list = converter.convert_time_series metric_prefix, resource_type,
                                                  resource_labels, view_data
      series_list.length.must_equal 1

      series = series_list.first
      series.metric.type.must_equal  "#{metric_prefix}/#{view.name}"
      assert_equal(series.metric.labels, {"column2"=>"test2", "column1"=>"test1"})
      series.resource.type.must_equal resource_type
      assert_equal(series.resource.labels, resource_labels)
      series.metric_kind.must_equal :GAUGE
      series.value_type.must_equal :DOUBLE
      series.points.length.must_equal 1
      series.points.first.interval.wont_be_nil
      series.points.first.value.double_value.must_equal 10.0
    end
  end
end
