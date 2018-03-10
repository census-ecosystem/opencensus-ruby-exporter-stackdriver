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

gem "google-cloud-trace"
gem "concurrent-ruby"

require "concurrent"
require "google/cloud/trace"
require "google/cloud/trace/v2"

module OpenCensus
  module Trace
    module Exporters
      ##
      # The Stackdriver exporter for OpenCensus Trace exports captured spans
      # to a Google Stackdriver project. It calls the Stackdriver Trace API in
      # a background thread pool.
      #
      class Stackdriver
        ##
        # Create a Stackdriver exporter.
        #
        # @param [String] project_id The project identifier for the Stackdriver
        #     Trace service you are connecting to. If you are running on Google
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
            mock_client: nil
          @project_id = final_project_id project_id

          @executor = create_executor max_threads, max_queue
          if auto_terminate_time
            terminate_at_exit! @executor, auto_terminate_time
          end

          if mock_client
            @client_promise =
              Concurrent::Promise.fulfill mock_client, executor: @executor
          else
            credentials = final_credentials credentials, scope
            scope ||= Google::Cloud.configure.trace.scope
            timeout ||= Google::Cloud.configure.trace.timeout
            client_config ||= Google::Cloud.configure.trace.client_config
            @client_promise = create_client_promise \
              @executor, credentials, scope, client_config, timeout
          end
        end

        ##
        # The project ID
        # @return [String]
        #
        attr_reader :project_id

        ##
        # Export spans to Stackdriver asynchronously.
        #
        # @param [Array<OpenCensus::Trace::Span>] spans The captured spans to
        #     export to Stackdriver
        #
        def export spans
          raise "Exporter is no longer running" unless @executor.running?

          @client_promise.execute
          export_promise = @client_promise.then do |client|
            export_as_batch(client, spans)
          end
          export_promise.on_error do |reason|
            warn "Unable to export to Stackdriver because: #{reason}"
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
        # pending spans have been sent.
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

        private

        # Create the executor
        def create_executor max_threads, max_queue
          if max_threads >= 1
            Concurrent::ThreadPoolExecutor.new \
              min_length: 1, max_length: max_threads,
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
            Google::Cloud::Trace::V2.new(
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
            Google::Cloud.configure.trace.project_id ||
            Google::Cloud.configure.project_id ||
            Google::Cloud.env.project_id
        end

        # Fall back to default credentials, and wrap in a creds object
        def final_credentials credentials, scope
          credentials ||=
            Google::Cloud.configure.trace.credentials ||
            Google::Cloud.configure.credentials ||
            Google::Cloud::Trace::Credentials.default(scope: scope)
          unless credentials.is_a? Google::Auth::Credentials
            credentials =
              Google::Cloud::Trace::Credentials.new credentials, scope: scope
          end
          credentials
        end

        # Export a list of spans in a single batch write, in the current thread
        def export_as_batch client, spans
          converter = Converter.new project_id
          span_protos = Array(spans).map { |span| converter.convert_span span }
          client.batch_write_spans "projects/#{project_id}", span_protos
        end
      end
    end
  end
end
