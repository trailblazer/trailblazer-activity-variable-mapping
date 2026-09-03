require "test_helper"
require "trailblazer/activity/dsl"

# FIXME: encapsulate
step_normalizer = Trailblazer::Activity::Railway.config.builder.normalizers[:step]

step_normalizer = Trailblazer::Circuit::Adds.(
  step_normalizer,

  # FIXME: the next step should be already there by Path/canonical.
  # extension/task_wrap
  [:apply_adds_to_task_wrap_pipeline, Trailblazer::Activity::DSL::Feature::Extension::TaskWrap::Normalizer::Node, :before, :build_task_wrap_node],

  [
    :variable_mapping, Trailblazer::Activity::VariableMapping::DSL::Normalizer::Node,
    :before, :normalize_wirings
  ],
)

normalizers = Trailblazer::Activity::Railway.config.builder.normalizers
Trailblazer::Activity::Railway.config.builder.normalizers = normalizers.merge(step: step_normalizer)

# extension/task_wrap
Trailblazer::Activity::Railway.config.builder = Trailblazer::Activity::Railway.config.builder.clone(merge: {adds_for_task_wrap: []})

Trailblazer::Developer.puts(Trailblazer::Activity::Railway.config.builder.normalizers[:step])

Trailblazer::Activity::DSL::Topology::Helper.include(Trailblazer::Activity::VariableMapping::DSL::Helper)

# Test I/O in {Topology}.
class ActivityIntegrationTest < Minitest::Spec
  # FIXME: stolen from dsl_test.rb.
  def self.my_capture_step(ctx, pollute: false, **kws)
    ctx[:captured] = [CU.inspect(ctx.to_h), CU.inspect(kws)]

    ctx[:pollute] = 1 if pollute
    true
  end

  my_capture_step = method(:my_capture_step)

  it "step only sees what is configured via In()" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step, id: :a,
        In() => [:model, :params]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success

    # the {:a} task cannot see {:seq}.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>["{:model=>nil, :params=>nil}", "{:model=>nil, :params=>nil}"]}}
  end
end
