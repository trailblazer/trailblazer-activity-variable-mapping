$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "trailblazer/activity/variable_mapping"
require "trailblazer/core"

require "minitest/autorun"

Minitest::Spec.class_eval do
  include Trailblazer::Core::Utils::AssertEqual
  include Trailblazer::Core::Utils::AssertRun

  def Pipeline(*args)
    Trailblazer::Circuit::Builder.Pipeline(*args)
  end
end
