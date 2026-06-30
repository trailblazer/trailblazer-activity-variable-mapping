require "test_helper"

# Test the normalizer
# DISCUSS: these are unit tests.
class DslTest < Minitest::Spec
  it "what" do
    lib_ctx, flow_options, signal = assert_run Trailblazer::Activity::VariableMapping::DSL::Normalizer.build_node, node: true,
      user_options: { # DISCUSS: naming is under construction.
        Trailblazer::Activity::VariableMapping::DSL::Inject() => [:http],
        Trailblazer::Activity::VariableMapping::DSL.Out() => ->(ctx, slug:, **) { {my_slug: slug} }
      },
      adds_for_task_wrap: [], # this is part of the DSL specification/convention/whatever.

      seq: [],
      use_application_ctx:  false,
      terminus: Trailblazer::Activity::Right

    assert_equal lib_ctx[:adds_for_task_wrap].size, 2
    assert_equal lib_ctx[:adds_for_task_wrap][0][2..3], [:before, :"task_wrap.call_task"]
    assert_equal lib_ctx[:adds_for_task_wrap][1][2..3], [:after, :"task_wrap.call_task"]
  end

  it "creates empty pipes when no filters wanted" do
    lib_ctx, flow_options, signal = assert_run Trailblazer::Activity::VariableMapping::DSL::Normalizer.build_node, node: true,

      user_options: { # DISCUSS: naming is under construction.
      },
      adds_for_task_wrap: [], # this is part of the DSL specification/convention/whatever.

      seq: [],
      use_application_ctx: false,
      terminus: Trailblazer::Activity::Left

    assert_equal lib_ctx[:adds_for_task_wrap], []
    assert_equal flow_options, {}
    # assert_equal signal, Trailblazer::Activity::Left
  end
end

class DslIntegrationTest < Minitest::Spec
  it "single Inject(): create private context, no vars added or exposed" do
    assert_dsl Trailblazer::Activity::VariableMapping::DSL::Inject() => [:http],
      expected: {captured: ["{}", "{}"]}
  end

  def my_capture_step(ctx, pollute: false, **kws)
    ctx[:pollute] = 1 if pollute

    ctx[:captured] = [CU.inspect(ctx.to_h), CU.inspect(kws)]
  end

  def mock_task_wrap_circuit(adds_for_task_wrap:, call_task: method(:my_capture_step), **)
    call_task_step = Trailblazer::Activity::Step.build(call_task)

    my_task_wrap = Trailblazer::Circuit::Builder.Pipeline(
      [:"task_wrap.call_task", node: call_task_step],
    )

    Trailblazer::Circuit::Adds.(my_task_wrap, *adds_for_task_wrap)
  end

  def build_adds_from_dsl(vm_options)
    lib_ctx, _ = assert_run Trailblazer::Activity::VariableMapping::DSL::Normalizer.build_node, node: true,
      user_options:  # DISCUSS: naming is under construction.
        vm_options,
      adds_for_task_wrap: [], # this is part of the DSL specification/convention/whatever.

      seq: [],
      use_application_ctx:  false,
      terminus: Trailblazer::Activity::Right
  end

  def assert_dsl(target_ctx: {}, expected:, **options)
    lib_ctx, _ = build_adds_from_dsl(options) # build the actual taskWrap steps.
    my_task_wrap = mock_task_wrap_circuit(**lib_ctx)

    lib_ctx, _ = assert_run my_task_wrap,
      seq: nil,
      use_application_ctx:  false, # FIXME: make unnecessary.
      target_ctx:           target_ctx,
      original_target_ctx:  {params: {}},
      terminus: Trailblazer::Activity::Right

    assert_equal lib_ctx[:target_ctx], {params: {}, **expected}
  end
end
