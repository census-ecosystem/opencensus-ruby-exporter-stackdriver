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

class LibraryTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::OpenCensus::Stackdriver::VERSION
  end

  def test_e2e
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
end
