# frozen_string_literal: true

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


gem "google-cloud-monitoring"
gem "concurrent-ruby"

require "concurrent"
require "google/cloud/monitoring"
require "google/cloud/monitoring/v3"

module OpenCensus
  ##
  # OpenCensus Stats provides a standard interface for distributed stats
  # recoding.
  #
  module Stats
    ##
    # The exporters module is a namespace for trace exporters.
    #
    module Exporters
      ##
      # The Stackdriver exporter for OpenCensus Stats exporter captured stats
      # to a Google Monitoring project. It calls the Monitoring API in
      # a background thread pool.
      #
      class Stackdriver
        # Default custom opencensus domain name
        # @return [Dtring]
        CUSTOM_OPENCENSUS_DOMAIN = "custom.googleapis.com/opencensus"

        # @private
        # Global resouce type
        GLOBAL_RESOURCE_TYPE = "global"

        # The project ID
        # @return [String]
        #
        attr_reader :project_id

        # Metric prefix
        # @return [String]
        attr_reader :metric_prefix

        # Metric resource type
        # @return [String]
        attr_reader :resource_type

        # Create a Stackdriver exporter.
        #
        # @param [String] project_id The project identifier for the Stackdriver
        #     Monitoring service you are connecting to. If you are running on
        #     Google
        #     Cloud hosting (e.g. Compute Engine, Kubernetes Engine, or App
        #     Engine), this parameter is optional and will default to the
        #     hosting project. Otherwise, it is required.
        # @param [String, Hash, Google::Auth::Credentials] credentials The
        #     Stackdriver API credentials, which can be a path to a keyfile as
        #     a String, the contents of a keyfile as a Hash, or a
        #     Google::Auth::Credentials object. If you are running on Google
        #     Cloud hosting (e.g. Compute Engine, Kubernetes Engine, or App
        #     Engine), this parameter is optional and will default to the
        #     credentials provided by the hosting project. Otherwise, it is
        #     required.
        # @param [String, Array<String>] scope The OAuth 2.0 scopes controlling
        #     the set of resources and operations the API client can access.
        #     Optional. Most applications can leave this set to the default.
        # @param [Integer] timeout The default timeout for API requests, in
        #     seconds. Optional.
        # @param [Hash] client_config An optional set of additional
        #     configuration values for the API connection.
        # @param [Integer] max_queue The maximum number of API requests that
        #     can be queued for background operation. If the queue exceeds this
        #     value, additional requests will be run in the calling thread
        #     rather than in the background. Set to 0 to allow the queue to
        #     grow indefinitely. Default is 1000.
        # @param [Integer] max_threads The maximum number of threads that can
        #     be spun up to handle API requests. Default is 1. If set to 0,
        #     backgrounding will be disabled and all requests will run in the
        #     calling thread.
        # @param [Integer] auto_terminate_time The time in seconds allotted to
        #     complete any pending background requests when Ruby is exiting.
        # @param [String] metric_prefix Prefix for stackdriver metric.
        # @param [String] resource_type Metric resource type
        #
        def initialize \
            project_id: nil,
            credentials: nil,
            scope: nil,
            timeout: nil,
            client_config: nil,
            max_queue: 1000,
            max_threads: 1,
            auto_terminate_time: 10,
            mock_client: nil,
            metric_prefix: nil,
            resource_type: nil
          @project_id = final_project_id project_id
          @metric_prefix = metric_prefix || CUSTOM_OPENCENSUS_DOMAIN
          @resource_type = resource_type || GLOBAL_RESOURCE_TYPE
          @executor = create_executor max_threads, max_queue

          if auto_terminate_time
            terminate_at_exit! @executor, auto_terminate_time
          end

          if mock_client
            @client_promise =
              Concurrent::Promise.fulfill mock_client, executor: @executor
          else
            credentials = final_credentials credentials, scope
            @client_promise = create_client_promise \
              @executor, credentials, scope, client_config, timeout
          end

          @converter = Converter.new @project_id
          @project_path = Google::Cloud::Monitoring::V3:: \
            MetricServiceClient.project_path @project_id
        end

        # Export stats to Monitoring service asynchronously.
        #
        # @param [Array<OpenCensus::Stats::ViewData>] views_data The captured
        #   stats data
        #
        def export views_data
          raise "Exporter is no longer running" unless @executor.running?

          return if views_data.nil? || views_data.empty?

          @client_promise.execute
          export_promise = @client_promise.then do |client|
            export_as_batch(client, views_data)
          end
          export_promise.on_error do |reason|
            warn "Unable to export to Monitering service because: #{reason}"
          end

          nil
        end

        ##
        # Returns true if this exporter is running and will accept further
        # export requests. Returns false once the exporter begins shutting down.
        #
        # @return [boolean]
        #
        def running?
          @executor.running?
        end

        ##
        # Returns true if this exporter has finished shutting down and all
        # pending stats have been sent.
        #
        # @return [boolean]
        #
        def shutdown?
          @executor.shutdown?
        end

        ##
        # Returns true if this exporter has begun shutting down and is no
        # longer accepting export requests, but is still running queued
        # requests in the background.
        #
        # @return [boolean]
        #
        def shuttingdown?
          @executor.shuttingdown?
        end

        ##
        # Begin shutting down the exporter gracefully. After this operation is
        # performed, the exporter will no longer accept export requests, but
        # will finish any pending requests in the background.
        #
        def shutdown
          @executor.shutdown
          self
        end

        ##
        # Begin shutting down the exporter forcefully. After this operation is
        # performed, the exporter will no longer accept export requests, and
        # will finish any currently running export requests, but will cancel
        # all requests that are still pending in the queue.
        #
        def kill
          @executor.kill
          self
        end

        ##
        # Wait for the exporter to finish shutting down.
        #
        # @param [Integer, nil] timeout A timeout in seconds, or nil for no
        #     timeout.
        # @return [boolean] true if the exporter is shut down, or false if the
        #     wait timed out.
        #
        def wait_for_termination timeout = nil
          @executor.wait_for_termination timeout
        end

        # Create a metric descriptor
        #
        # An error will be raised if there is
        # already a metric descriptor created with the same name
        # but it has a different aggregation or keys.
        #
        # @param [OpenCensus::Stats::View] view
        # @return [Google::Api::MetricDescriptor]
        #
        def create_metric_descriptor view
          metric_descriptor = @converter.convert_metric_descriptor(
            view,
            metric_prefix
          )
          metric_name = Google::Cloud::Monitoring::V3:: \
            MetricServiceClient.metric_descriptor_path(
              project_id,
              metric_descriptor.type
            )

          @client_promise.execute
          descriptor_create_promise = @client_promise.then do |client|
            client.create_metric_descriptor metric_name, metric_descriptor
          end
          descriptor_create_promise.value!
        end

        private

        # Create the executor
        def create_executor max_threads, max_queue
          if max_threads >= 1
            Concurrent::ThreadPoolExecutor.new \
              min_threads: 1, max_threads: max_threads,
              max_queue: max_queue, fallback_policy: :caller_runs,
              auto_terminate: false
          else
            Concurrent::ImmediateExecutor.new
          end
        end

        # Create the client promise.
        # We create the client lazily so grpc doesn't get initialized until
        # we actually need it. This is important because if it is intialized
        # too early, before a fork, it can go into a bad state.
        def create_client_promise executor, credentials, scopes, client_config,
                                  timeout
          Concurrent::Promise.new executor: executor do
            Google::Cloud::Monitoring::Metric.new(
              credentials: credentials,
              scopes: scopes,
              client_config: client_config,
              timeout: timeout,
              lib_name: "opencensus",
              lib_version: OpenCensus::Stackdriver::VERSION
            )
          end
        end

        # Set up an at_exit hook that shuts the exporter down.
        def terminate_at_exit! executor, timeout
          at_exit do
            executor.shutdown
            unless executor.wait_for_termination timeout
              executor.kill
              executor.wait_for_termination timeout
            end
          end
        end

        # Fall back to default project ID
        def final_project_id project_id
          project_id ||
            Google::Cloud.configure.project_id ||
            Google::Cloud.env.project_id
        end

        # Fall back to default credentials, and wrap in a creds object
        def final_credentials credentials, scope
          credentials ||=
            Google::Cloud.configure.credentials ||
            Google::Cloud::Monitoring::V3::Credentials.default(scope: scope)
          unless credentials.is_a? Google::Auth::Credentials
            credentials = Google::Cloud::Monitoring::V3::Credentials.new(
              credentials,
              scope: scope
            )
          end
          credentials
        end

        # Export a list of stats in the current thread
        def export_as_batch client, views_data
          time_series = views_data.map do |view_data|
            @converter.convert_time_series(
              metric_prefix,
              resource_type,
              view_data
            )
          end

          client.create_time_series @project_path, time_series.flatten!
        end
      end
    end
  end
end
