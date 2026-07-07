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
      exec_context_for_provider: self,

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
    let(:options) { {dsl.Inject() => [:http]} }

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

    it "we can have multiple Inject with one configured variable" do
      options = {
        **self.options,
        dsl.Inject() => [:db],
        dsl.Inject() => [:logger],
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
        dsl.Inject() => [:db, :logger]
      }

      assert_dsl **options,
        expected: {captured: ["{:random=>1, :http=>2, :logger=>Object}", "{:random=>1, :http=>2, :logger=>Object}"]}, target_ctx: {random: 1, http: 2, logger: Object}

      # test that :db is also injected.
      assert_dsl **options,
        expected: {captured: ["{:random=>1, :db=>Object}", "{:random=>1, :db=>Object}"]}, target_ctx: {random: 1, db: Object}
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

    it "with Out() => [], all private variables are discarded" do
      options = {
        **self.options,
        dsl.Out() => []
      }

      assert_dsl **options,
        expected: {}, target_ctx: {pollute: true}
    end

    it "with Out() => [], injected variables are discarded, too!" do
      options = {
        **self.options,
        dsl.Out() => []
      }

      assert_dsl **options,
        expected: {}, target_ctx: {pollute: true, http: Object}
    end

    it "injected variables can be exposed" do
      options = {
        **self.options,
        dsl.Out() => [:http]
      }

      assert_dsl **options,
        expected: {http: Object}, target_ctx: {pollute: true, http: Object}

      # However, they're always exposed, no Conditional, yet. We'd need Outject().
      assert_dsl **options,
        expected: {http: nil}, target_ctx: {pollute: true}
    end
  end


  describe "Inject => ->(*) { snippet }" do
    let(:options) do
      options = {
        dsl.Inject(:http) => ->(ctx, **kws) { [CU.inspect(ctx), CU.inspect(kws)] }
      }
    end

    it "if variable is absent, it defaults. the block can see the {ctx} + kws" do
      assert_dsl **options,
        expected: {
          captured: [ctx = "{:params=>{}, :http=>[\"{:params=>{}}\", \"{:params=>{}}\"]}", ctx] # {:http} is defaulted.
        }, target_ctx: {params: {}}
    end

    it "if present, the defaulting is skipped" do
      assert_dsl **options,
        expected: {captured: [ctx = "{:params=>{}, :http=>Object}", ctx]},
        target_ctx: {params: {}, http: Object}
    end
  end

  describe "Inject => {:instance_method}" do
    let(:options) do
      options = {
        dsl.Inject(:http) => :my_inject_defaulter
      }
    end

    def my_inject_defaulter(ctx, **kws)
      [CU.inspect(ctx), CU.inspect(kws)]
    end

    it "if variable is absent, it defaults. the block can see the {ctx} + kws" do
      assert_dsl **options,
        exec_context_for_provider: self,
        expected: {
          captured: [ctx = "{:params=>{}, :http=>[\"{:params=>{}}\", \"{:params=>{}}\"]}", ctx] # {:http} is defaulted.
        }, target_ctx: {params: {}}
    end

    it "if present, the defaulting is skipped" do
      assert_dsl **options,
        exec_context_for_provider: self,
        expected: {captured: [ctx = "{:params=>{}, :http=>Object}", ctx]},
        target_ctx: {params: {}, http: Object}
    end
  end

  # TODO: override
  describe "Inject(:variable, override: true) => ->(*) { snippet }" do
    let(:options) do
      options = {
        dsl.Inject(:http, override: true) => :my_inject_defaulter
      }
    end

    def my_inject_defaulter(ctx, **kws)
      [CU.inspect(ctx), CU.inspect(kws)]
    end

    it "if variable is absent, it defaults. the block can see the {ctx} + kws" do
      what_filter_sees = ["{:params=>{}}", "{:params=>{}}"]

      assert_dsl **options,
        exec_context_for_provider: self,
        expected: {
          captured: [ctx = "{:params=>{}, :http=>#{what_filter_sees}}", ctx] # {:http} is defaulted.
        }, target_ctx: {params: {}}
    end

    it "if present, it is still defaulted as we're overriding" do
      # the override filter sees the "original" {:http} variable.
      what_filter_sees = ["{:params=>{}, :http=>Object}", "{:params=>{}, :http=>Object}"]

      assert_dsl **options,
        exec_context_for_provider: self,
        expected: {
          # the task sees what the override filter sees.
          captured: [ctx = "{:params=>{}, :http=>#{what_filter_sees}}", ctx] # {:http} is still defaulted.
        }, target_ctx: {params: {}, http: Object}
    end
  end

  describe "In()" do
    let(:options) { {dsl.In() => [:http]} }

    it "with empty ctx, :http will be set to {nil}" do
      assert_dsl **options, expected: {captured: ["{:http=>nil}", "{:http=>nil}"]}
    end

    it "In() will pass {:http} if it is present in ctx" do
      assert_dsl **options, expected: {captured: ["{:http=>Object}", "{:http=>Object}"]},
        target_ctx: {http: Object}
    end




  end

  describe "In() => ->{}" do
    it "In() => ->(*) { snippet } whitelists and doesn't pass other variables" do
      # raise "after that, implement Inject() :override"

      options = {
        dsl.In() => ->(ctx, **kws) { {a: [CU.inspect(ctx), CU.inspect(kws)]} }
      }

      what_filter_a_sees = ["{:from_outside=>1}", "{:from_outside=>1}"]

      assert_dsl **options,
        expected: {captured: ["{:a=>#{what_filter_a_sees}}", "{:a=>#{what_filter_a_sees}}"]},
        target_ctx: {from_outside: 1}
    end
  end

  describe "In() => :instance_method" do
    it "In() => :instance_method whitelists and doesn't pass other variables" do
      options = {
        dsl.In() => :my_input,
      }

      def my_input(ctx, **kws)
        {a: [CU.inspect(ctx), CU.inspect(kws)]}
      end

      what_filter_a_sees = ["{:from_outside=>1}", "{:from_outside=>1}"]

      assert_dsl **options,
        expected: {captured: ["{:a=>#{what_filter_a_sees}}", "{:a=>#{what_filter_a_sees}}"]},
        target_ctx: {from_outside: 1}
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
      exec_context_for_provider: self, # DISCUSS: is that the right place?
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
