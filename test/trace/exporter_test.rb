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

require_relative "../test_helper"

describe OpenCensus::Trace::Exporters::Stackdriver do
  let(:project_id) { "my-project" }
  let(:trace_id) { "0123456789abcdef0123456789abcdef" }
  let(:span1_id) { "0123456789abcdef" }
  let(:span2_id) { "fedcba9876543210" }
  let(:name1) { OpenCensus::Trace::TruncatableString.new "span1" }
  let(:name2) { OpenCensus::Trace::TruncatableString.new "span2" }
  let(:start1_time) { Time.at(1000) }
  let(:end1_time) { Time.at(2000) }
  let(:start2_time) { Time.at(1200) }
  let(:end2_time) { Time.at(1800) }
  let(:span1) {
    OpenCensus::Trace::Span.new \
      trace_id, span1_id, name1, start1_time, end1_time,
      parent_span_id: ""
  }
  let(:span2) {
    OpenCensus::Trace::Span.new \
      trace_id, span2_id, name2, start2_time, end2_time,
      parent_span_id: span1_id
  }

  it "should send spans" do
    mock_client = Minitest::Mock.new
    # concurrent-ruby tests values against nil. Need to make sure the mock
    # responds appropriately.
    def mock_client.nil?; false; end

    converter = OpenCensus::Trace::Exporters::Stackdriver::Converter.new project_id
    expected_span_protos = [span1, span2].map { |span| converter.convert_span span }
    mock_client.expect :batch_write_spans, nil, ["projects/my-project", expected_span_protos]

    exporter = OpenCensus::Trace::Exporters::Stackdriver.new \
      project_id: project_id,
      mock_client: mock_client

    exporter.export [span1, span2]
    exporter.shutdown
    exporter.wait_for_termination(2)

    mock_client.verify
  end

  it "should not export an empty span list" do
    mock_client = Minitest::Mock.new
    # concurrent-ruby tests values against nil. Need to make sure the mock
    # responds appropriately.
    def mock_client.nil?; false; end

    converter = OpenCensus::Trace::Exporters::Stackdriver::Converter.new project_id

    exporter = OpenCensus::Trace::Exporters::Stackdriver.new \
      project_id: project_id,
      mock_client: mock_client

    # Since mock_client doesn't expect the batch_write_spans method to be
    # called, it should raise the NoMethodError if this happens
    exporter.export []

    exporter.shutdown
    exporter.wait_for_termination(2)

    mock_client.verify
  end
end
