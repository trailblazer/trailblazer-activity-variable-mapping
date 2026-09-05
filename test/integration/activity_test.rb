require "test_helper"
require "trailblazer/activity/dsl"

# FIXME: encapsulate
[
  # Trailblazer::Activity::Path,
  Trailblazer::Activity::Railway,
  # Trailblazer::Activity::FastTrack
].each do |topology|
  activity, builder, helper_forwarder = Trailblazer::Activity::DSL::Topology.build(
    builder: topology.config.builder,
    default_options: {adds_for_task_wrap: []},

    helpers: {
      Trailblazer::Activity::VariableMapping::DSL::Helper => [:In, :Out, :Inject]
    },
    adds: [
      # FIXME: the next step should be already there by Path/canonical.
      # extension/task_wrap
      [:apply_adds_to_task_wrap_pipeline, Trailblazer::Activity::DSL::Feature::Extension::TaskWrap::Normalizer::Node, :before, :build_task_wrap_node],

      [
        :variable_mapping, Trailblazer::Activity::VariableMapping::DSL::Normalizer::Node,
        :before, :normalize_wirings
      ],
    ],
  )

  topology.config.builder = builder
  topology.extend helper_forwarder
end

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
      step my_capture_step,
        In() => [:model, :params]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # the {my_capture_step} step cannot see {:seq}.
    # we can see {:captured} on the outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>["{:model=>nil, :params=>nil}", "{:model=>nil, :params=>nil}"]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # Since we don't allow :pollute, the my_capture_step doesn't see it.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>["{:model=>nil, :params=>nil}", "{:model=>nil, :params=>nil}"]}}
  end

  it "without Out(), all variables are visible on the outside" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params, :pollute]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # the {my_capture_step} step cannot see {:seq}.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>["{:model=>nil, :params=>nil, :pollute=>nil}", "{:model=>nil, :params=>nil}"]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we can see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: 1, :captured=>["{:model=>nil, :params=>nil, :pollute=>true}", "{:model=>nil, :params=>nil}"]}}
  end

  it "with Out(), we only see {:captured}" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params, :pollute],
        Out() => [:captured]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    #
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>["{:model=>nil, :params=>nil, :pollute=>nil}", "{:model=>nil, :params=>nil}"]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we cannot see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>["{:model=>nil, :params=>nil, :pollute=>true}", "{:model=>nil, :params=>nil}"]}}
  end

  it "" do
    my_railway = Class.new(Trailblazer::Activity::Railway) do
      step my_capture_step,
        In() => [:model, :params],
        Inject() => [:pollute],
        Out() => [:captured]
    end

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success
    # {:pollute} is absent in target_ctx and thus not visible inside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], :captured=>["{:model=>nil, :params=>nil}", "{:model=>nil, :params=>nil}"]}}

    lib_ctx, _ = assert_run my_railway, seq: [], terminus: :success, target_ctx: {seq: [], pollute: true}
    # we cannot see pollute outside.
    assert_equal lib_ctx, {:target_ctx=>{:seq=>[], pollute: true, :captured=>["{:pollute=>true, :model=>nil, :params=>nil}", "{:model=>nil, :params=>nil}"]}}
  end
end
