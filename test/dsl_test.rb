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
  let(:dsl) { Trailblazer::Activity::VariableMapping::DSL }

  describe "#Inject" do
    let(:options) { {dsl::Inject() => [:http]} }

    it "with empty ctx, nothing gets injected" do
      assert_dsl **options, expected: {captured: ["{}", "{}"]}
    end

    it "with variables in ctx, those are visible" do
      assert_dsl **options, expected: {captured: ["{:random=>1}", "{:random=>1}"]}, target_ctx: {random: 1}
    end

    it "with variables in ctx + inject variable, all are visible" do
      assert_dsl **options, expected: {captured: ["{:random=>1, :http=>2}", "{:random=>1, :http=>2}"]}, target_ctx: {random: 1, http: 2}
    end

    it "injected variable can be {nil}" do
      assert_dsl **options, expected: {captured: ["{:random=>1, :http=>nil}", "{:random=>1, :http=>nil}"]}, target_ctx: {random: 1, http: nil}
    end

    it "without Out(), {pollute} is visible outside" do
      assert_dsl **options,
        expected: {
          captured: ["{:pollute=>true}", "{}"],
          pollute: 1 # outside, we see the pollution.
        },
        target_ctx: {pollute: true}
    end

    it "without Out() + inject variable, {pollute} is visible outside" do
      assert_dsl **options,
        expected: {
          captured: ["{:pollute=>true, :http=>Object}", "{:http=>Object}"],
          pollute: 1 # outside, we see the pollution.
        },
        target_ctx: {pollute: true, http: Object}
    end

    it "we can have multiple Inject with one configured variable" do
      options = {
        **self.options,
        dsl::Inject() => [:db],
        dsl::Inject() => [:logger],
      }

      assert_dsl **options,
        expected: {captured: ["{:random=>1, :http=>2, :logger=>Object}", "{:random=>1, :http=>2, :logger=>Object}"]}, target_ctx: {random: 1, http: 2, logger: Object}

      # test that :db is also injected.
      assert_dsl **options,
        expected: {captured: ["{:random=>1, :db=>Object}", "{:random=>1, :db=>Object}"]}, target_ctx: {random: 1, db: Object}
    end

    it "we can also configure multiple variables" do
      options = {
        **self.options,
        dsl::Inject() => [:db, :logger]
      }

      assert_dsl **options,
        expected: {captured: ["{:random=>1, :http=>2, :logger=>Object}", "{:random=>1, :http=>2, :logger=>Object}"]}, target_ctx: {random: 1, http: 2, logger: Object}

      # test that :db is also injected.
      assert_dsl **options,
        expected: {captured: ["{:random=>1, :db=>Object}", "{:random=>1, :db=>Object}"]}, target_ctx: {random: 1, db: Object}
    end
  end



  def my_capture_step(ctx, pollute: false, **kws)
    ctx[:captured] = [CU.inspect(ctx.to_h), CU.inspect(kws)]

    ctx[:pollute] = 1 if pollute
    true
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
