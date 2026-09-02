require "test_helper"
require "trailblazer/activity/dsl"

# FIXME: encapsulate
Trailblazer::Activity::Path::Normalizer::Step = Trailblazer::Circuit::Adds.(
  Trailblazer::Activity::Path::Normalizer::Step,
  [
    :variable_mapping, Trailblazer::Activity::VariableMapping::DSL::Normalizer::Node,
    :before, :normalize_wirings
  ],
)

# Test I/O in {Topology}.
class ActivityIntegrationTest < Minitest::Spec
  it "what" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do

    end
  end
end
