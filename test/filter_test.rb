require "test_helper"

class FilterTest < Minitest::Spec
  let(:filter_lib_ctx_options) { {aggregate: {}} }

  StepInterface = Trailblazer::Circuit::Task::Adapter::StepInterface

  Filter = Trailblazer::Activity::VariableMapping::Runtime::Filter

  it "read a variable from the {application_ctx}, like In() => {:slug => :my_slug}" do
    my_node = Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [:read_variable_from_application_ctx, {}],
      read_name: :slug,
      write_name: :my_slug,
    )

    lib_ctx, flow_options, signal = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      terminus: {:my_slug=>"generator-1"} # DISCUSS: value-on-signal

    assert_equal lib_ctx, {aggregate: {:my_slug=>"generator-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  it "invoke a callable, wrap its value with a hash" do
    my_input_provider = ->(ctx, slug:, **) { slug.upcase }

    my_node = Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [my_input_provider, {}],
      write_name: :my_slug,
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  it "invoke an {:instance_method}, wrap the value" do
    my_exec_context = Class.new do
      def downcase_slug(ctx, slug:, **)
        slug.upcase
      end
    end.new

# FIXME: remove write_name where it's nil
    my_node = Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [:downcase_slug, exec_context: my_exec_context],
      read_name: nil,
      write_name: :my_slug,
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  it "invoke a callable, no wrapping" do
    my_input_provider = ->(ctx, slug:, **) { {my_slug: slug.upcase} }

    my_node = Filter.build_node(
      id: nil,
      args_for_step_build: [my_input_provider, {}],
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  describe "Out" do
    it "Out(pass_outer_ctx: true)" do
      my_provider = ->(ctx, outer_ctx:, **kws) {
        {
          my_slug: [CU.inspect(ctx), CU.inspect(outer_ctx), CU.inspect(kws)]
        }
      }

      my_node = Filter::Out::PassOuterCtx.build_node(
        id: nil,
        args_for_step_build: [my_provider, {}],
        write_name: :my_slug,
      )

      ctx_from_call_task = {bogus: true, slug: "0x666"}.freeze # this is the ctx produced by the call_task.

      target_ctx = Trailblazer::Activity::VariableMapping::Context.new(
        ctx_from_call_task,
        {},
        {params: {id: 1}} # this is what the Out filter sees as the "outer_ctx".
      ).freeze

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        **filter_lib_ctx_options,
        target_ctx: target_ctx,
        terminus: expected_aggregate = {
          :my_slug => [
            "#<struct Trailblazer::Activity::VariableMapping::Context shadowed={:bogus=>true, :slug=>\"0x666\"}, mutable={:outer_ctx=>{:params=>{:id=>1}}}, original_ctx=nil>", # ctx contains {:outer_ctx}, it's a new Context instance, not identical to {target_ctx}.
            "{:params=>{:id=>1}}", # this is the outer_ctx.
            "{:bogus=>true, :slug=>\"0x666\"}" # the remaining kws.
          ],
        }

      assert_equal lib_ctx, {
        aggregate: expected_aggregate,
        target_ctx: target_ctx # Note that we don't see {:outer_ctx} here. that's because we Scope the MergeToCircuitOptions node (WIP).
      }
      assert_equal flow_options, {}
    end
  end

  describe "Inject" do
    it "writes value to aggregate if it's present (Conditioned)" do
      my_node = Filter::Conditioned.build_node(
        id: nil,
        write_name: :slug,
        read_name: :slug,
      )

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
        **filter_lib_ctx_options,
        terminus: {:slug=>"generator-1"},
        signal: Object

      assert_equal lib_ctx, {aggregate: {:slug=>"generator-1"}, target_ctx: original_target_ctx} # we could read {:slug}.
      assert_equal flow_options, {}
    end

    it "works even if the incoming signal is something other than {nil}" do
      my_node = Filter::Conditioned.build_node(
        id: nil,
        write_name: :slug,
        read_name: :slug,
      )

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
        **filter_lib_ctx_options,
        terminus: {:slug=>"generator-1"} # DISCUSS: scoping?

      assert_equal lib_ctx, {aggregate: {:slug=>"generator-1"}, target_ctx: original_target_ctx} # we could read {:slug}.
      assert_equal flow_options, {}
    end

    it "Conditioned always uses the same circuit" do
      skip
      require "benchmark/memory"

      Benchmark.memory do |x|
        x.report("rebuild") do
          my_node = Filter::Conditioned.build_node(
            id: nil,
            write_name: :slug,
            read_name: :slug,
          )

          my_node_2 = Filter::Conditioned.build_node(
            id: nil,
            write_name: :slug,
            read_name: :slug,
          )
        end

        x.compare!
      end

      raise
    end
  end

  describe "Defaulted" do
    it "defaults value if absent, and reads value otherwise (Defaulted)" do
      my_provider_for_default = ->(ctx, params:, **) { params[:id] }

      my_node = Filter::Defaulted.build_node(
        id: nil,
        args_for_default_provider: [my_provider_for_default, {}],
        read_name: :global_id,
        write_name: :my_global_id,
      )

      original_target_ctx = {global_id: 1}.freeze

      # raise "how do we get variable_present_in_application_ctx?'s Left to point to the defaulting step?"
      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        target_ctx: original_target_ctx,
        **filter_lib_ctx_options,
        terminus: {my_global_id: 1}

      assert_equal lib_ctx, {:aggregate=>{:my_global_id=>1}, target_ctx: original_target_ctx}

      original_target_ctx = {params: {id: 2}}
      # in this run, we let the defaulting logic kick in.
      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        target_ctx: original_target_ctx,
        **filter_lib_ctx_options,
        terminus: {my_global_id: 2}

      assert_equal lib_ctx, {:aggregate=>{:my_global_id=>2}, target_ctx: original_target_ctx}
    end

    it "accepts {:instance_method} as provider" do
      def my_provider_for_default(ctx, params:, **)
        params[:id]
      end

      my_node = Filter::Defaulted.build_node(
        id: nil,
        args_for_default_provider: [:my_provider_for_default, {exec_context: self}],
        read_name: :global_id,
        write_name: :my_global_id,
      )

      original_target_ctx = {params: {id: 1}}.freeze

      # only test the case where we call the {:instance_method} provider.
      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        target_ctx: original_target_ctx,
        **filter_lib_ctx_options,
        terminus: {my_global_id: 1}

      assert_equal lib_ctx, {:aggregate=>{:my_global_id=>1}, target_ctx: original_target_ctx}
    end

    it "Defaulted doesn't run block when variable is present" do
      my_provider_for_default = ->(*) { raise }

        my_node = Filter::Defaulted.build_node(
          id: nil,
          args_for_default_provider: [my_provider_for_default, {}],
          read_name: :global_id,
          write_name: :my_global_id,
        )

        original_target_ctx = {global_id: 1}.freeze

        # raise "how do we get variable_present_in_application_ctx?'s Left to point to the defaulting step?"
        lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
          target_ctx: original_target_ctx,
          **filter_lib_ctx_options,
          terminus: {my_global_id: 1}

        assert_equal lib_ctx, {:aggregate=>{:my_global_id=>1}, target_ctx: original_target_ctx}
    end

    it "Override" do
      my_provider = ->(ctx, params:, **) { params[:id] }

      my_node = Filter::Override.build_node(
        id: nil,
        args_for_step_build: [my_provider, {}],
        write_name: :my_id,
      )

      target_ctx = {params: {id: 1}.freeze}.freeze

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        target_ctx: target_ctx,
        **filter_lib_ctx_options,
        terminus: {my_id: 1}

      assert_equal lib_ctx, {:aggregate=>{:my_id=>1}, target_ctx: target_ctx}

      # we still add our :my_id to aggregate, even if it's present
      target_ctx = {my_id: 2, params: {id: 1}.freeze}.freeze

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        target_ctx: target_ctx,
        **filter_lib_ctx_options,
        terminus: {my_id: 1}

      assert_equal lib_ctx, {:aggregate=>{:my_id=>1}, target_ctx: target_ctx}
    end
  end
end
