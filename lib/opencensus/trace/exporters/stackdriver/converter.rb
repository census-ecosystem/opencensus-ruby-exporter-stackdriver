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

require "google/devtools/cloudtrace/v2/trace_pb"
require "google/protobuf/well_known_types"

module OpenCensus
  module Trace
    module Exporters
      class Stackdriver
        ##
        # An object that converts OpenCensus span data objects to Stackdriver
        # Trace V2 protos.
        #
        # You should use one converter instance to convert the spans for a
        # single export request, because the converter will keep track of and
        # omit duplicate stack traces. Use a new converter instance for the
        # next request.
        #
        # @private
        #
        class Converter
          ##
          # @private
          # Alias for the V2 Cloudtrace protos namespace
          #
          TraceProtos = Google::Devtools::Cloudtrace::V2

          ##
          # @private
          # Attribute key for Stackdriver trace agent
          #
          AGENT_KEY = "g.co/agent".freeze

          ##
          # @private
          # Attribute value for Stackdriver trace agent
          #
          AGENT_VALUE =
            OpenCensus::Trace::TruncatableString.new \
              "opencensus-ruby [#{::OpenCensus::VERSION}] ruby-stackdriver-" \
              "exporter [#{::OpenCensus::Stackdriver::VERSION}]"

          ##
          # Create a converter
          #
          # @param [String] project_id Google project ID
          #
          def initialize project_id
            @project_id = project_id
            @stack_trace_hash_ids = {}
          end

          # rubocop:disable Metrics/AbcSize

          ##
          # Convert a span object.
          #
          # @param [OpenCensus::Trace::Span] obj OpenCensus span object
          # @return [Google::Devtools::Cloudtrace::V2::Span] The generated
          #     proto
          #
          def convert_span obj
            TraceProtos::Span.new \
              name: make_resource_name(@project_id, obj.trace_id, obj.span_id),
              span_id: obj.span_id,
              parent_span_id: obj.parent_span_id || "",
              display_name: convert_truncatable_string(obj.name),
              start_time: convert_time(obj.start_time),
              end_time: convert_time(obj.end_time),
              attributes:
                convert_attributes(obj.attributes,
                                   obj.dropped_attributes_count,
                                   include_agent_attribute: true),
              stack_trace:
                convert_stack_trace(obj.stack_trace, obj.dropped_frames_count,
                                    obj.stack_trace_hash_id),
              time_events:
                convert_time_events(obj.time_events,
                                    obj.dropped_annotations_count,
                                    obj.dropped_message_events_count),
              links: convert_links(obj.links, obj.dropped_links_count),
              status: convert_optional_status(obj.status),
              same_process_as_parent_span:
                convert_optional_bool(obj.same_process_as_parent_span),
              child_span_count: convert_optional_int32(obj.child_span_count)
          end

          # rubocop:enable Metrics/AbcSize

          ##
          # Make a span resource name.
          #
          # @param [String] project_id The project ID
          # @param [String] trace_id The project ID
          # @param [String] span_id The project ID
          # @return [String] The resource na,e
          #
          def make_resource_name project_id, trace_id, span_id
            "projects/#{project_id}/traces/#{trace_id}/spans/#{span_id}"
          end

          ##
          # Create a truncatable string proto.
          #
          # @param [String] str The string
          # @param [Integer] truncated_byte_count The number of bytes omitted.
          #     Defaults to 0.
          # @return [Google::Devtools::Cloudtrace::V2::TruncatableString] The
          #     generated proto
          #
          def make_truncatable_string str, truncated_byte_count = 0
            TraceProtos::TruncatableString.new \
              value: str,
              truncated_byte_count: truncated_byte_count
          end

          ##
          # Convert a truncatable string object.
          #
          # @param [OpenCensus::Trace::TruncatableString] obj OpenCensus
          #     truncatable string object
          # @return [Google::Devtools::Cloudtrace::V2::TruncatableString] The
          #     generated proto
          #
          def convert_truncatable_string obj
            make_truncatable_string obj.value, obj.truncated_byte_count
          end

          ##
          # Convert a time object.
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
          # Convert a value that can be used for an attribute.
          #
          # @param [OpenCensus::Trace::TruncatableString, Integer, boolean]
          #     obj Object to convert
          # @return [Google::Devtools::Cloudtrace::V2::AttributeValue] The
          #     generated proto
          #
          def convert_attribute_value obj
            case obj
            when OpenCensus::Trace::TruncatableString
              TraceProtos::AttributeValue.new \
                string_value: convert_truncatable_string(obj)
            when Integer
              TraceProtos::AttributeValue.new int_value: obj
            when true, false
              TraceProtos::AttributeValue.new bool_value: obj
            end
          end

          ##
          # Convert an attributes hash
          #
          # @param [Hash] attributes The map of attribute values to convert
          # @param [Integer] dropped_attributes_count Number of dropped
          # @param [Boolean] include_agent_attribute Include the `g.co/agent`
          #     attribute in the result. Default is false.
          # @return [Google::Devtools::Cloudtrace::V2::Attributes] The
          #     generated proto
          #
          def convert_attributes attributes, dropped_attributes_count,
                                 include_agent_attribute: false
            attribute_map = {}
            if include_agent_attribute
              attribute_map[AGENT_KEY] = convert_attribute_value AGENT_VALUE
            end
            attributes.each do |k, v|
              attribute_map[k] = convert_attribute_value v
            end
            TraceProtos::Span::Attributes.new \
              attribute_map: attribute_map,
              dropped_attributes_count: dropped_attributes_count
          end

          ##
          # Convert a single stack frame as a Thread::Backtrace::Location
          #
          # @param [Thread::Backtrace::Location] frame The backtrace element to
          #     convert
          # @return [Google::Devtools::Cloudtrace::V2::StackTrace::StackFrame]
          #     The generated proto
          #
          def convert_stack_frame frame
            TraceProtos::StackTrace::StackFrame.new \
              function_name: make_truncatable_string(frame.label),
              file_name: make_truncatable_string(frame.path),
              line_number: frame.lineno
          end

          ##
          # Convert a full backtrace.
          #
          # @param [Array<Thread::Backtrace::Location>] backtrace The backtrace
          #     element array to convert
          # @param [Integer] dropped_frames_count Frames that were dropped
          # @param [Integer] stack_trace_hash_id Hash of the data
          # @return [Google::Devtools::Cloudtrace::V2::StackTrace] The
          #     generated proto
          #
          def convert_stack_trace backtrace, dropped_frames_count,
                                  stack_trace_hash_id
            if @stack_trace_hash_ids[stack_trace_hash_id]
              return TraceProtos::StackTrace.new \
                stack_trace_hash_id: stack_trace_hash_id
            end
            @stack_trace_hash_ids[stack_trace_hash_id] = true
            frame_protos = backtrace.map { |frame| convert_stack_frame(frame) }
            frames_proto = TraceProtos::StackTrace::StackFrames.new \
              frame: frame_protos,
              dropped_frames_count: dropped_frames_count
            TraceProtos::StackTrace.new \
              stack_frames: frames_proto,
              stack_trace_hash_id: stack_trace_hash_id
          end

          ##
          # Convert an annotation object
          #
          # @param [OpenCensus::Trace::Annotation] annotation The annotation
          #     object to convert
          # @return
          #     [Google::Devtools::Cloudtrace::V2::Span::TimeEvent::Annotation]
          #     The generated proto
          #
          def convert_annotation annotation
            annotation_proto = TraceProtos::Span::TimeEvent::Annotation.new \
              description: convert_truncatable_string(annotation.description),
              attributes:
                convert_attributes(annotation.attributes,
                                   annotation.dropped_attributes_count)
            TraceProtos::Span::TimeEvent.new \
              time: convert_time(annotation.time),
              annotation: annotation_proto
          end

          ##
          # Convert a message event object
          #
          # @param [OpenCensus::Trace::MessageEvent] message_event The message
          #     event object to convert
          # @return
          #    [Google::Devtools::Cloudtrace::V2::Span::TimeEvent::MessageEvent]
          #    The generated proto
          #
          def convert_message_event message_event
            message_event_proto =
              TraceProtos::Span::TimeEvent::MessageEvent.new \
                type: message_event.type,
                id: message_event.id,
                uncompressed_size_bytes: message_event.uncompressed_size,
                compressed_size_bytes: message_event.compressed_size
            Google::Devtools::Cloudtrace::V2::Span::TimeEvent.new \
              time: convert_time(message_event.time),
              message_event: message_event_proto
          end

          ##
          # Convert a list of time event objects
          #
          # @param [Array<OpenCensus::Trace::TimeEvent>] time_events The time
          #     event objects to convert
          # @param [Integer] dropped_annotations_count Number of dropped
          #     annotations
          # @param [Integer] dropped_message_events_count Number of dropped
          #     message events
          # @return [Google::Devtools::Cloudtrace::V2::Span::TimeEvents] The
          #     generated proto
          #
          def convert_time_events time_events, dropped_annotations_count,
                                  dropped_message_events_count
            time_event_protos = time_events.map do |time_event|
              case time_event
              when OpenCensus::Trace::Annotation
                convert_annotation time_event
              when OpenCensus::Trace::MessageEvent
                convert_message_event time_event
              else
                nil
              end
            end.compact
            TraceProtos::Span::TimeEvents.new \
              time_event: time_event_protos,
              dropped_annotations_count: dropped_annotations_count,
              dropped_message_events_count: dropped_message_events_count
          end

          ##
          # Convert a link object
          #
          # @param [OpenCensus::Trace::Link] link The link object to convert
          # @return [Google::Devtools::Cloudtrace::V2::Span::Link] The
          #     generated proto
          #
          def convert_link link
            TraceProtos::Span::Link.new \
              trace_id: link.trace_id,
              span_id: link.span_id,
              type: link.type,
              attributes:
                convert_attributes(link.attributes,
                                   link.dropped_attributes_count)
          end

          ##
          # Convert a list of link objects
          #
          # @param [Array<OpenCensus::Trace::Link>] links The link objects to
          #     convert
          # @param [Integer] dropped_links_count Number of dropped links
          # @return [Google::Devtools::Cloudtrace::V2::Span::Links] The
          #     generated proto
          #
          def convert_links links, dropped_links_count
            TraceProtos::Span::Links.new \
              link: links.map { |link| convert_link link },
              dropped_links_count: dropped_links_count
          end

          ##
          # Convert a nullable status object
          #
          # @param [OpenCensus::Trace::Status, nil] status The status object to
          #     convert, or nil if absent
          # @return [Google::Rpc::Status, nil] The generated proto, or nil
          #
          def convert_optional_status status
            return nil if status.nil?

            Google::Rpc::Status.new code: status.code, message: status.message
          end

          ##
          # Convert a nullable boolean object
          #
          # @param [boolean, nil] value The value to convert, or nil if absent
          # @return [Google::Protobuf::BoolValue, nil] Generated proto, or nil
          #
          def convert_optional_bool value
            return nil if value.nil?

            Google::Protobuf::BoolValue.new value: value
          end

          ##
          # Convert a nullable int32 object
          #
          # @param [Integer, nil] value The value to convert, or nil if absent
          # @return [Google::Protobuf::Int32Value, nil] Generated proto, or nil
          #
          def convert_optional_int32 value
            return nil if value.nil?

            Google::Protobuf::Int32Value.new value: value
          end
        end
      end
    end
  end
end
