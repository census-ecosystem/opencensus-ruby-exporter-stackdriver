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

describe OpenCensus::Trace::Exporters::Stackdriver::Converter do
  let(:agent_key) { OpenCensus::Trace::Exporters::Stackdriver::Converter::AGENT_KEY }
  let(:project_id) { "my-project" }
  let(:converter) {
    OpenCensus::Trace::Exporters::Stackdriver::Converter.new project_id
  }
  let(:simple_string) { "hello" }
  let(:string_truncated_bytes) { 6 }
  let(:truncatable_string) {
    OpenCensus::Trace::TruncatableString.new \
      simple_string, truncated_byte_count: string_truncated_bytes
  }
  let(:trace_id) { "0123456789abcdef0123456789abcdef" }
  let(:trace_id2) { "fedcba9876543210fedcba9876543210" }
  let(:span_id) { "0123456789abcdef" }
  let(:span_id2) { "fedcba9876543210" }
  let(:annotation_desc) { "This is an annotation" }
  let(:annotation) {
    OpenCensus::Trace::Annotation.new \
      OpenCensus::Trace::TruncatableString.new(annotation_desc),
      attributes: {"foo" => truncatable_string},
      dropped_attributes_count: 1,
      time: Time.at(1001)
  }
  let(:message_event) {
    OpenCensus::Trace::MessageEvent.new \
      OpenCensus::Trace::MessageEvent::SENT, 12345, 100, time: Time.at(1002)
  }
  let(:link1) {
    OpenCensus::Trace::Link.new trace_id, span_id,
      type: OpenCensus::Trace::Link::CHILD_LINKED_SPAN,
      attributes: {"foo" => truncatable_string},
      dropped_attributes_count: 1
  }
  let(:link2) {
    OpenCensus::Trace::Link.new trace_id2, span_id2,
      type: OpenCensus::Trace::Link::PARENT_LINKED_SPAN,
      attributes: {"foo" => 123},
      dropped_attributes_count: 2
  }
  let(:loc1) {
    OpenStruct.new label: "foo", path: "/path/to/file.rb", lineno: 100
  }
  let(:loc2) {
    OpenStruct.new label: "bar", path: "/path/to/another/file.rb", lineno: 200
  }
  let(:status) {
    OpenCensus::Trace::Status.new 404, "Not found"
  }

  describe "#convert_truncatable_string" do
    it "converts a fully populated object" do
      proto = converter.convert_truncatable_string truncatable_string
      proto.value.must_equal simple_string
      proto.truncated_byte_count.must_equal string_truncated_bytes
    end
  end

  describe "#convert_attribute_value" do
    it "converts a string" do
      proto = converter.convert_attribute_value truncatable_string
      proto.string_value.value.must_equal simple_string
      proto.string_value.truncated_byte_count.must_equal string_truncated_bytes
      proto.value.must_equal :string_value
    end

    it "converts an integer" do
      proto = converter.convert_attribute_value(-1000)
      proto.int_value.must_equal(-1000)
      proto.value.must_equal :int_value
    end

    it "converts a boolean" do
      proto = converter.convert_attribute_value false
      proto.bool_value.must_equal false
      proto.value.must_equal :bool_value
    end
  end

  describe "#convert_attributes" do
    it "converts three attributes of different types" do
      input_attrs = {"str" => truncatable_string, "int" => -1000, "bool" => false}
      proto = converter.convert_attributes input_attrs, 2
      proto.attribute_map["str"].string_value.value.must_equal simple_string
      proto.attribute_map["str"].string_value.truncated_byte_count.must_equal string_truncated_bytes
      proto.attribute_map["str"].value.must_equal :string_value
      proto.attribute_map["int"].int_value.must_equal(-1000)
      proto.attribute_map["int"].value.must_equal :int_value
      proto.attribute_map["bool"].bool_value.must_equal false
      proto.attribute_map["bool"].value.must_equal :bool_value
      proto.dropped_attributes_count.must_equal 2
    end

    it "converts well-known attribute names" do
      input_attrs = {
        "http.host" => OpenCensus::Trace::TruncatableString.new("www.google.com"),
        "http.method" => OpenCensus::Trace::TruncatableString.new("POST"),
        "http.path" => OpenCensus::Trace::TruncatableString.new("/hello/world"),
        "http.route" => OpenCensus::Trace::TruncatableString.new("/hello/:entity"),
        "http.user_agent" => OpenCensus::Trace::TruncatableString.new("OpenCensus/1.0"),
        "http.status_code" => 200
      }
      proto = converter.convert_attributes input_attrs, 2
      proto.attribute_map["/http/host"].string_value.value.must_equal "www.google.com"
      proto.attribute_map["/http/method"].string_value.value.must_equal "POST"
      proto.attribute_map["/http/path"].string_value.value.must_equal "/hello/world"
      proto.attribute_map["/http/route"].string_value.value.must_equal "/hello/:entity"
      proto.attribute_map["/http/user_agent"].string_value.value.must_equal "OpenCensus/1.0"
      proto.attribute_map["/http/status_code"].int_value.must_equal 200
      proto.attribute_map["http.host"].must_be_nil
      proto.attribute_map["http.method"].must_be_nil
      proto.attribute_map["http.path"].must_be_nil
      proto.attribute_map["http.route"].must_be_nil
      proto.attribute_map["http.user_agent"].must_be_nil
      proto.attribute_map["http.status_code"].must_be_nil
      proto.dropped_attributes_count.must_equal 2
    end

    it "has include_agent_attribute default to false" do
      input_attrs = {"str" => truncatable_string}
      proto = converter.convert_attributes input_attrs, 2
      proto.attribute_map[agent_key].must_be_nil
    end

    it "honors include_agent_attribute=true" do
      input_attrs = {"str" => truncatable_string}
      proto = converter.convert_attributes input_attrs, 2, include_agent_attribute: true
      proto.attribute_map[agent_key].string_value.value.must_match(/^opencensus-ruby/)
    end
  end

  describe "#convert_stack_frame" do
    it "converts an ordinary location" do
      proto = converter.convert_stack_frame loc1
      proto.function_name.value.must_equal "foo"
      proto.function_name.truncated_byte_count.must_equal 0
      proto.file_name.value.must_equal "/path/to/file.rb"
      proto.file_name.truncated_byte_count.must_equal 0
      proto.line_number.must_equal 100
    end
  end

  describe "#convert_stack_trace" do
    it "converts an ordinary location" do
      proto = converter.convert_stack_trace [loc1, loc2], 3, 12345
      proto.stack_frames.frame.length.must_equal 2
      proto.stack_frames.frame[0].function_name.value.must_equal "foo"
      proto.stack_frames.frame[1].function_name.value.must_equal "bar"
      proto.stack_frames.dropped_frames_count.must_equal 3
      proto.stack_trace_hash_id.must_equal 12345
    end

    it "omits a duplicate" do
      proto1 = converter.convert_stack_trace [loc1, loc2], 3, 12345
      proto1.stack_frames.wont_be_nil
      proto1.stack_trace_hash_id.must_equal 12345
      proto2 = converter.convert_stack_trace [loc1, loc2], 3, 12345
      proto2.stack_frames.must_be_nil
      proto2.stack_trace_hash_id.must_equal 12345
    end
  end

  describe "#convert_annotation" do
    it "converts an annotation" do
      proto = converter.convert_annotation annotation
      proto.annotation.description.value.must_equal annotation_desc
      proto.annotation.description.truncated_byte_count.must_equal 0
      proto.annotation.attributes.dropped_attributes_count.must_equal 1
      proto.annotation.attributes.attribute_map["foo"].string_value.value.must_equal simple_string
      proto.annotation.attributes.attribute_map["foo"].string_value.truncated_byte_count.must_equal string_truncated_bytes
      proto.annotation.attributes.attribute_map[agent_key].must_be_nil
      proto.time.seconds.must_equal 1001
    end
  end

  describe "#convert_message_event" do
    it "converts a message event" do
      proto = converter.convert_message_event message_event
      proto.message_event.type.must_equal :SENT
      proto.message_event.id.must_equal 12345
      proto.message_event.uncompressed_size_bytes.must_equal 100
      proto.message_event.compressed_size_bytes.must_equal 0
      proto.time.seconds.must_equal 1002
    end
  end

  describe "#convert_time_events" do
    it "converts a set of time events" do
      proto = converter.convert_time_events [message_event, annotation], 4, 5
      proto.time_event.length.must_equal 2
      proto.time_event[0].message_event.type.must_equal :SENT
      proto.time_event[1].annotation.description.value.must_equal annotation_desc
      proto.dropped_annotations_count.must_equal 4
      proto.dropped_message_events_count.must_equal 5
    end
  end

  describe "#convert_link" do
    it "converts a link" do
      proto = converter.convert_link link1
      proto.trace_id.must_equal trace_id
      proto.span_id.must_equal span_id
      proto.type.must_equal :CHILD_LINKED_SPAN
      proto.attributes.dropped_attributes_count.must_equal 1
      proto.attributes.attribute_map["foo"].string_value.value.must_equal simple_string
    end
  end

  describe "#convert_links" do
    it "converts a set of links" do
      proto = converter.convert_links [link1, link2], 3
      proto.link.length.must_equal 2
      proto.link[0].type.must_equal :CHILD_LINKED_SPAN
      proto.link[1].type.must_equal :PARENT_LINKED_SPAN
      proto.dropped_links_count.must_equal 3
    end
  end

  describe "#convert_status" do
    it "converts a status" do
      proto = converter.convert_optional_status status
      proto.code.must_equal 404
      proto.message.must_equal "Not found"
    end

    it "converts nil" do
      proto = converter.convert_optional_status nil
      proto.must_be_nil
    end
  end

  describe "#convert_span" do
    it "converts a basic span" do
      span = OpenCensus::Trace::Span.new \
        trace_id, span_id, truncatable_string, Time.at(1000), Time.at(2000),
        parent_span_id: span_id2,
        attributes: {"foo" => 123},
        dropped_attributes_count: 1,
        stack_trace: [loc1, loc2],
        dropped_frames_count: 2,
        time_events: [annotation, message_event],
        dropped_annotations_count: 3,
        dropped_message_events_count: 4,
        links: [link1, link2],
        dropped_links_count: 5,
        status: status,
        same_process_as_parent_span: true,
        child_span_count: 6
      proto = converter.convert_span span
      proto.name.must_equal "projects/#{project_id}/traces/#{trace_id}/spans/#{span_id}"
      proto.span_id.must_equal span_id
      proto.parent_span_id.must_equal span_id2
      proto.display_name.value.must_equal simple_string
      proto.start_time.seconds.must_equal 1000
      proto.end_time.seconds.must_equal 2000
      proto.attributes.attribute_map["foo"].int_value.must_equal 123
      proto.attributes.attribute_map[agent_key].string_value.value.must_match(/^opencensus-ruby/)
      proto.attributes.dropped_attributes_count.must_equal 1
      proto.stack_trace.stack_frames.frame[0].function_name.value.must_equal "foo"
      proto.stack_trace.stack_frames.dropped_frames_count.must_equal 2
      proto.time_events.time_event[0].time.seconds.must_equal 1001
      proto.time_events.time_event[0].annotation.description.value.must_equal annotation_desc
      proto.time_events.time_event[1].time.seconds.must_equal 1002
      proto.time_events.time_event[1].message_event.type.must_equal :SENT
      proto.time_events.dropped_annotations_count.must_equal 3
      proto.time_events.dropped_message_events_count.must_equal 4
      proto.links.link[0].type.must_equal :CHILD_LINKED_SPAN
      proto.links.link[1].type.must_equal :PARENT_LINKED_SPAN
      proto.links.dropped_links_count.must_equal 5
      proto.status.code.must_equal 404
      proto.same_process_as_parent_span.value.must_equal true
      proto.child_span_count.value.must_equal 6
    end

    it "caches repeated stack traces" do
      span = OpenCensus::Trace::Span.new \
        trace_id, span_id, truncatable_string, Time.at(1000), Time.at(2000),
        parent_span_id: span_id2,
        attributes: {"foo" => 123},
        dropped_attributes_count: 1,
        stack_trace: [loc1, loc2],
        dropped_frames_count: 2,
        time_events: [annotation, message_event],
        dropped_annotations_count: 3,
        dropped_message_events_count: 4,
        links: [link1, link2],
        dropped_links_count: 5,
        status: status,
        same_process_as_parent_span: true,
        child_span_count: 6
      proto1 = converter.convert_span span
      proto2 = converter.convert_span span
      proto1.stack_trace.stack_frames.wont_be_nil
      proto2.stack_trace.stack_frames.must_be_nil
      proto2.stack_trace.stack_trace_hash_id.must_equal proto1.stack_trace.stack_trace_hash_id
    end
  end
end
