# frozen_string_literal: true

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


module OpenCensus
  module Stats
    module Exporters
      class Stackdriver
        ##
        # An object that converts OpenCensus stats data objects to Monitoring
        # service protos
        #
        # @private
        #
        class Converter
          ##
          # Create a converter
          #
          # @param [String] project_id Google project ID
          #
          def initialize project_id
            @project_id = project_id
          end

          # Convert view to metric descriptor
          #
          # @param [OpenCensus::Stats:View] view Stats view
          # @param [String] metric_prefix Metric prefix name
          # @return [Google::Api::MetricDescriptor]
          #
          def convert_metric_descriptor view, metric_prefix
            descriptor = Google::Api::MetricDescriptor.new(
              type: make_metric_type(metric_prefix, view.name),
              display_name: view.measure.name,
              metric_kind: convert_metric_kind(view.aggregation),
              value_type: convert_metric_value_type(view),
              unit: view.measure.unit,
              labels: convert_labels(view.columns)
            )

            descriptor.description = view.description if view.description
            descriptor
          end

          # Conver to lables
          #
          # @param [Array<String>] names
          # @return [Array<Google::Api::LabelDescriptor>]
          def convert_labels names
            names.map do |name|
              Google::Api::LabelDescriptor.new(
                key: name,
                value_type: Google::Api::LabelDescriptor::ValueType::STRING
              )
            end
          end

          # Convert to metric view type.
          #
          # @param [OpenCensus::Stats:View] view Stats view
          # @return [Symbol] Metric value type
          #
          def convert_metric_value_type view
            case view.aggregation
            when OpenCensus::Stats::Aggregation::Distribution
              Google::Api::MetricDescriptor::ValueType::DISTRIBUTION
            when OpenCensus::Stats::Aggregation::Count
              Google::Api::MetricDescriptor::ValueType::INT64
            when OpenCensus::Stats::Aggregation::Sum,
                OpenCensus::Stats::Aggregation::LastValue
              if view.measure.int64?
                Google::Api::MetricDescriptor::ValueType::INT64
              else
                Google::Api::MetricDescriptor::ValueType::DOUBLE
              end
            end
          end

          # Convert to metric kind
          #
          # @param [OpenCensus::Stats:Aggregation::LastValue,
          #   OpenCensus::Stats:Aggregation::Sum,
          #   OpenCensus::Stats:Aggregation::Count,
          #   OpenCensus::Stats:Aggregation::Distribution] aggregation
          #   Aggregation type
          # @return [Symbol] Metric kind type
          #
          def convert_metric_kind aggregation
            last_value_class = OpenCensus::Stats::Aggregation::LastValue

            if aggregation.instance_of? last_value_class
              return Google::Api::MetricDescriptor::MetricKind::GAUGE
            end

            Google::Api::MetricDescriptor::MetricKind::CUMULATIVE
          end

          # Convert view data to time series list
          #
          # @param [String] metric_prefix Metric prefix name
          # @param [String] resource_type Metric resource type
          # @param [OpenCensus::Stats::ViewData] view_data Stats view data
          # @return [Array[Google::Monitoring::V3::TimeSeries]]
          #
          def convert_time_series metric_prefix, resource_type, view_data
            view = view_data.view

            view_data.data.map do |tag_values, aggr_data|
              series = Google::Monitoring::V3::TimeSeries.new(
                metric: {
                  type: make_metric_type(metric_prefix, view.name),
                  labels: Hash[view.columns.zip tag_values]
                },
                resource: {
                  type: resource_type,
                  labels: {
                    "project_id" => @project_id
                  }
                },
                metric_kind: convert_metric_kind(view.aggregation),
                value_type: convert_metric_value_type(view)
              )

              series.points << convert_point(
                view_data.start_time,
                aggr_data.time,
                view.measure,
                aggr_data
              )

              series
            end
          end

          # Convert aggr data to time series point proto
          #
          # @param [Time] start_time Start time
          # @param [Time] end_time Start time
          # @param [OpenCensus::Stats:Measure] measure Measure details
          # @param [OpenCensus::Stats:AggregationData] aggr_data Aggregated data
          # @raise [TypeError] If invalid aggr data type.
          # @return [Google::Monitoring::V3::Point]
          def convert_point start_time, end_time, measure, aggr_data
            case aggr_data
            when OpenCensus::Stats::AggregationData::Distribution
              create_distribution_point start_time, end_time, aggr_data
            when OpenCensus::Stats::AggregationData::LastValue
              create_number_point(
                start_time,
                start_time,
                aggr_data.value,
                measure
              )
            when OpenCensus::Stats::AggregationData::Sum,
                OpenCensus::Stats::AggregationData::Count
              create_number_point(
                start_time,
                end_time,
                aggr_data.value,
                measure
              )
            else
              raise TypeError, "invalid aggregation type : #{aggr_data.class}"
            end
          end

          # Create a distribution point
          # @param [Time] start_time Start time
          # @param [Time] end_time Start time
          # @param [OpenCensus::Stats::AggregationData::Distribution] aggr_data
          # @return [Google::Monitoring::V3::Point]
          #
          def create_distribution_point start_time, end_time, aggr_data
            value = {
              count: aggr_data.count,
              mean: aggr_data.mean,
              sum_of_squared_deviation: aggr_data.sum_of_squared_deviation,
              bucket_options: {
                explicit_buckets: {
                  bounds: [0].concat(aggr_data.buckets)
                }
              },
              bucket_counts: [0].concat(aggr_data.bucket_counts)
            }

            Google::Monitoring::V3::Point.new(
              interval: {
                start_time: convert_time(start_time),
                end_time: convert_time(end_time)
              },
              value: {
                distribution_value: value
              }
            )
          end

          # Create a number point
          # @param [Time] start_time Start time
          # @param [Time] end_time Start time
          # @param [Integer, Float] value
          # @param [OpenCensus::Stats::Measure] measure Measure defination
          # @return [Google::Monitoring::V3::Point]
          #
          def create_number_point start_time, end_time, value, measure
            value = if measure.int64?
                      { int64_value: value }
                    else
                      { double_value: value }
                    end

            Google::Monitoring::V3::Point.new(
              interval: {
                start_time: convert_time(start_time),
                end_time: convert_time(end_time)
              },
              value: value
            )
          end

          # Convert time object to protobuf timestamp
          #
          # @param [Time] time Ruby Time object
          # @return [Google::Protobuf::Timestamp] The generated proto
          #
          def convert_time time
            proto = Google::Protobuf::Timestamp.new
            proto.from_time(time)
            proto
          end

          ##
          # Make make metric type
          #
          # @param [String] metric_prefix The metric prefix
          # @param [String] name The name of the mertic view
          # @return [String] The metric type path
          #
          def make_metric_type metric_prefix, name
            "#{metric_prefix}/#{name}"
          end
        end
      end
    end
  end
end
